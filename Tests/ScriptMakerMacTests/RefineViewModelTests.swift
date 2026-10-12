import XCTest
@testable import ScriptMakerMac

@MainActor
final class RefineViewModelTests: XCTestCase {
    private func makeViewModel(_ mock: MockRefineTransport) -> RefineViewModel {
        RefineViewModel(config: AppConfig(), service: RefineService(transport: mock))
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
}
