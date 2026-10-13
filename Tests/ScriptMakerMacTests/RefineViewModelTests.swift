import XCTest
@testable import ScriptMakerMac

@MainActor
final class RefineViewModelTests: XCTestCase {
    /// Isolated UserDefaults per VM: apiBaseURL/provider/variation persist
    /// via didSet, so sharing .standard across tests poisons later tests
    /// (e.g. a blank URL persisted by the bad-URL test breaks every
    /// subsequent refine() at normalize).
    private func makeViewModel(_ mock: MockRefineTransport) -> RefineViewModel {
        let defaults = UserDefaults(suiteName: "test-refine-\(UUID().uuidString)")!
        return RefineViewModel(config: AppConfig(defaults: defaults),
                               service: RefineService(transport: mock))
    }

    func testEmptyScriptFailsLoudWithoutNetwork() async {
        let mock = MockRefineTransport()
        let vm = makeViewModel(mock)
        vm.script = "   "
        await vm.refine()
        XCTAssertEqual(mock.calls, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.output)
        XCTAssertFalse(vm.isLoading)
    }

    func testBadURLFailsLoudWithoutNetwork() async {
        let mock = MockRefineTransport()
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        vm.apiBaseURL = "   "
        await vm.refine()
        XCTAssertEqual(mock.calls, 0)
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(vm.output)
    }

    func testSuccessSetsOutput() async {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertEqual(mock.calls, 1)
        XCTAssertNil(vm.errorMessage)
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.output?.refinedScripts.count, 2)
        XCTAssertEqual(vm.output?.detectedIssues.first?.category, .emotionInconsistency)
        XCTAssertEqual(vm.selectedVariation, 0)
    }

    func testServerErrorSurfacesMessage() async {
        let mock = MockRefineTransport()
        mock.stub = (Data("boom".utf8), 500)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertNil(vm.output)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.errorMessage?.contains("500") == true)
    }

    func testIssueDraftAddRemove() throws {
        let vm = makeViewModel(MockRefineTransport())
        XCTAssertTrue(vm.issueDrafts.isEmpty)
        vm.addIssue()
        XCTAssertEqual(vm.issueDrafts.count, 1)
        let draft = try XCTUnwrap(vm.issueDrafts.first)
        vm.removeIssue(draft)
        XCTAssertTrue(vm.issueDrafts.isEmpty)
    }

    func testToggleFocus() {
        let vm = makeViewModel(MockRefineTransport())
        vm.toggleFocus(.cameraContinuity)
        XCTAssertTrue(vm.selectedFocus.contains(.cameraContinuity))
        vm.toggleFocus(.cameraContinuity)
        XCTAssertFalse(vm.selectedFocus.contains(.cameraContinuity))
    }

    func testCanGoReflectsScriptAndLoading() {
        let vm = makeViewModel(MockRefineTransport())
        XCTAssertFalse(vm.canGo)
        vm.script = "INT. OFFICE - DAY"
        XCTAssertTrue(vm.canGo)
        vm.isLoading = true
        XCTAssertFalse(vm.canGo)
    }

    func testResolvedURLStringShowsExecuteTarget() {
        let vm = makeViewModel(MockRefineTransport())
        vm.apiBaseURL = "http://127.0.0.1:8080/"
        XCTAssertEqual(vm.resolvedURLString, "http://127.0.0.1:8080/execute")
        vm.apiBaseURL = "http://127.0.0.1:8080/execute"
        XCTAssertEqual(vm.resolvedURLString, "http://127.0.0.1:8080/execute")
        vm.apiBaseURL = "   "
        XCTAssertEqual(vm.resolvedURLString, "")
    }

    func testLogRecordsRequestAndResponse() async {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertFalse(vm.logLines.isEmpty)
        XCTAssertTrue(vm.logLines[0].text.hasPrefix("POST http://127.0.0.1:8080/execute"))
        XCTAssertEqual(vm.logLines[0].kind, .request)
        XCTAssertTrue(vm.logLines.contains { $0.kind == .response && $0.text.contains("200 OK") })
    }

    func testLogClearedOnEachGo() async {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        let firstCount = vm.logLines.count
        XCTAssertGreaterThan(firstCount, 0)
        await vm.refine()
        XCTAssertEqual(vm.logLines.count, firstCount)
        XCTAssertTrue(vm.logLines[0].text.hasPrefix("POST http://127.0.0.1:8080/execute"))
    }

    func testLogRecordsError() async {
        let mock = MockRefineTransport()
        mock.stub = (Data("boom".utf8), 500)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertTrue(vm.logLines.contains { $0.kind == .error })
    }

    func testLogShowsRawServerBodyOnEnvelopeError() async {
        let mock = MockRefineTransport()
        mock.stub = (Data("""
            {"error": {"code": "provider_execution_failed",
                       "message": "Provider execution failed. Check provider authentication."}}
            """.utf8), 500)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertTrue(vm.logLines.contains {
            $0.kind == .error && $0.text.contains("provider_execution_failed")
        })
        XCTAssertTrue(vm.logLines.contains {
            $0.kind == .error && $0.text.contains("body:") && $0.text.contains("Check provider authentication")
        }, "the exact server bytes must appear in the log")
    }

    func testLogShowsRawServerBodyOnFlatError() async {
        let mock = MockRefineTransport()
        mock.stub = (Data("""
            {"code": "provider_execution_failed", "message": "Provider execution failed."}
            """.utf8), 500)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertTrue(vm.logLines.contains {
            $0.kind == .error && $0.text.contains("body:") && $0.text.contains("provider_execution_failed")
        }, "non-envelope errors must also log the raw server bytes")
    }

    func testStreamingLogsProgressAndResult() async {
        let mock = MockRefineTransport()
        mock.streamEvents = [
            RefineStreamEvent(name: "progress", data: "analyzing script"),
            RefineStreamEvent(name: "result", data: refineOutputJSON),
        ]
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        vm.streamProgress = true
        await vm.refine()
        XCTAssertTrue(mock.lastURL?.absoluteString.contains("status=true") == true)
        XCTAssertTrue(vm.logLines.contains { $0.kind == .info && $0.text.contains("analyzing script") })
        XCTAssertNotNil(vm.output)
        XCTAssertEqual(vm.output?.refinedScripts.count, 2)
    }

    func testLogExpandsOnGo() async {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = makeViewModel(mock)
        vm.script = "INT. OFFICE - DAY"
        vm.logExpanded = false
        await vm.refine()
        XCTAssertTrue(vm.logExpanded)
    }

    func testSelectedVariationPersistsAcrossLaunches() {
        let defaults = UserDefaults(suiteName: "test-refine-variation")!
        defaults.removePersistentDomain(forName: "test-refine-variation")
        let config = AppConfig(defaults: defaults)
        let vm = RefineViewModel(config: config, service: RefineService(transport: MockRefineTransport()))
        vm.selectedVariation = 1
        XCTAssertEqual(config.refineSelectedVariation, 1)
        let relaunched = RefineViewModel(config: AppConfig(defaults: defaults),
                                         service: RefineService(transport: MockRefineTransport()))
        XCTAssertEqual(relaunched.selectedVariation, 1)
        defaults.removePersistentDomain(forName: "test-refine-variation")
    }

    func testAdoptOutputRestoresPersistedVariation() async {
        let defaults = UserDefaults(suiteName: "test-refine-adopt")!
        defaults.removePersistentDomain(forName: "test-refine-adopt")
        let config = AppConfig(defaults: defaults)
        config.refineSelectedVariation = 1
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = RefineViewModel(config: config, service: RefineService(transport: mock))
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertEqual(vm.selectedVariation, 1, "persisted tab should survive a new result")
        defaults.removePersistentDomain(forName: "test-refine-adopt")
    }

    func testAdoptOutputClampsOutOfRangeVariation() async {
        let defaults = UserDefaults(suiteName: "test-refine-clamp")!
        defaults.removePersistentDomain(forName: "test-refine-clamp")
        let config = AppConfig(defaults: defaults)
        config.refineSelectedVariation = 9
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let vm = RefineViewModel(config: config, service: RefineService(transport: mock))
        vm.script = "INT. OFFICE - DAY"
        await vm.refine()
        XCTAssertEqual(vm.selectedVariation, 1, "clamped to the last variation")
        defaults.removePersistentDomain(forName: "test-refine-clamp")
    }

    func testRequestPreviewJSONShowsEnvelope() {
        let vm = makeViewModel(MockRefineTransport())
        vm.script = "INT. OFFICE - DAY"
        vm.outputCount = 3
        vm.provider = .antigravity
        vm.toggleFocus(.textCorrection)
        let json = vm.requestPreviewJSON
        XCTAssertTrue(json.contains("ScriptRefiner"))
        XCTAssertTrue(json.contains("antigravity"))
        XCTAssertTrue(json.contains("output_count"))
        XCTAssertTrue(json.contains("correction_focus"))
        XCTAssertTrue(json.contains("INT. OFFICE - DAY"))
    }
}
