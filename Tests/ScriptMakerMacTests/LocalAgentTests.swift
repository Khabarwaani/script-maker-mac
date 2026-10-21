import XCTest
import AgentAtom
import KhabarwaaniAgent
import TerminalAgentSession
@testable import ScriptMakerMac

private let syntheticSchema = #"{"type":"object","additionalProperties":false,"required":["title","settings","values"],"properties":{"title":{"type":"string","minLength":1},"count":{"type":"integer","default":2,"minimum":1,"maximum":5},"weight":{"type":"number","default":0.5},"extra":{"type":"string"},"settings":{"type":"object","additionalProperties":false,"required":["enabled","mode","note"],"properties":{"enabled":{"type":"boolean","default":true},"mode":{"type":"string","enum":["fast","slow"],"default":"slow"},"note":{"type":["string","null"],"default":null}}},"values":{"type":"array","minItems":1,"items":{"type":"object","required":["name"],"additionalProperties":false,"properties":{"name":{"type":"string","minLength":1}}}}}}"#

private struct SyntheticSpec: ModelledSpec {
    struct Input: Codable, Sendable {
        struct Settings: Codable, Sendable { let enabled: Bool; let mode: String; let note: String? }
        struct Item: Codable, Sendable { let name: String }
        let title: String; let settings: Settings; let values: [Item]
        let count: Int?; let weight: Double?; let extra: String?
    }
    struct Output: Codable, Sendable { let ok: Bool }
    static let identity = Identity(id: "SyntheticNewAgent", name: "Synthetic New Agent", version: "1.0.0")
    static let role = "Synthetic test agent"
    let instructions = "Return JSON."
    let input: Input
    var output: Output?
}
private func syntheticEntry() -> AgentCatalogEntry {
    .init(spec: SyntheticSpec.self, inputSchemaJSON: syntheticSchema, makeSpec: { SyntheticSpec(input: $0) })
}
private func syntheticDefinition(version: String = "1.0.0", executable: Bool = true, web: Bool = false) throws -> LocalAgentDefinition {
    .init(agentID: "SyntheticNewAgent", name: "Synthetic New Agent", version: version,
        schema: try AgentInputSchema(json: syntheticSchema), requiresWebResearch: web, isExecutable: executable)
}
private func filledDraft(_ schema: AgentInputSchema) -> AgentInputDraft {
    var draft = AgentInputDraft(schema: schema, required: true)
    draft.fields["title"]!.text = "A title"
    var item = AgentInputDraft(schema: schema.properties["values"]!.items!, required: true)
    item.fields["name"]!.text = "An item"
    draft.fields["values"]!.items = [item]
    return draft
}
private func payload() throws -> String {
    let schema = try AgentInputSchema(json: syntheticSchema)
    return try filledDraft(schema).value(schema: schema, required: true)!.json()
}

final class AgentInputSchemaTests: XCTestCase {
    func testDefaultsEnumsBooleanNestedArrayAndOptionalNullPreserveTypes() throws {
        let schema = try AgentInputSchema(json: syntheticSchema)
        let draft = filledDraft(schema)
        let value = try XCTUnwrap(draft.value(schema: schema, required: true))
        try schema.validate(value)
        XCTAssertEqual(value.object["count"], .number(2))
        XCTAssertEqual(value.object["weight"], .number(0.5))
        XCTAssertNil(value.object["extra"])
        XCTAssertEqual(value.object["settings"]?.object["enabled"], .bool(true))
        XCTAssertEqual(value.object["settings"]?.object["mode"], .string("slow"))
        XCTAssertEqual(value.object["settings"]?.object["note"], .null)
        XCTAssertEqual(value.object["values"]?.array.first?.object["name"], .string("An item"))
        XCTAssertEqual(try JSONDecoder().decode(AgentJSON.self, from: Data(value.json().utf8)), value)
    }
    func testInvalidNumericEditsRemainUnchangedAndFailBeforeExecution() throws {
        let schema = try AgentInputSchema(json: syntheticSchema)
        var draft = filledDraft(schema)
        draft.fields["count"]!.text = "-"
        XCTAssertThrowsError(try draft.value(schema: schema, required: true))
        XCTAssertEqual(draft.fields["count"]?.text, "-")
        draft.fields["count"]!.text = "1.5"
        XCTAssertThrowsError(try schema.validate(draft.value(schema: schema, required: true)!))
        draft.fields["count"]!.text = "9007199254740993"
        XCTAssertThrowsError(try draft.value(schema: schema, required: true))
        draft.fields["count"]!.text = "6"
        XCTAssertThrowsError(try schema.validate(draft.value(schema: schema, required: true)!))
    }
    func testRequiredFieldsArrayBoundsAndUnknownKeysFail() throws {
        let schema = try AgentInputSchema(json: syntheticSchema)
        var draft = filledDraft(schema)
        draft.fields["title"]!.text = "  "
        XCTAssertThrowsError(try schema.validate(draft.value(schema: schema, required: true)!))
        draft.fields["title"]!.text = "Title"
        draft.fields["values"]!.items = []
        XCTAssertThrowsError(try schema.validate(draft.value(schema: schema, required: true)!))
        XCTAssertThrowsError(try schema.validate(.object(["surprise": .bool(true)])))
        XCTAssertThrowsError(try AgentInputSchema(json: #"{"type":"object","properties":{"bad":{"$ref":"missing"}}}"#))
    }
    func testOmittedAndExplicitNullDifferAndNonNullableNullFails() throws {
        let schema = try AgentInputSchema(json: syntheticSchema)
        var draft = filledDraft(schema)
        draft.fields["extra"]!.included = true
        draft.fields["extra"]!.text = ""
        XCTAssertEqual(try draft.value(schema: schema, required: true)?.object["extra"], .string(""))
        draft.fields["extra"]!.isNull = true
        XCTAssertThrowsError(try schema.validate(draft.value(schema: schema, required: true)!))
        let nullableEnum = try AgentInputSchema(json: #"{"type":"object","properties":{"value":{"type":["string","null"],"enum":["allowed"]}}}"#)
        XCTAssertThrowsError(try nullableEnum.validate(.object(["value": .null])))
    }
}

@MainActor
final class LocalAgentViewModelTests: XCTestCase {
    func testAgentChangesSelectLatestAndOldFormDraftRemainsStable() async throws {
        let old = try syntheticDefinition()
        let latest = try syntheticDefinition(version: "2.0.0")
        let other = LocalAgentDefinition(agentID: "Other", name: "Other", version: "1.0.0", schema: old.schema)
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner(definitions: [old, latest, other]))
        await vm.refreshProviders()
        vm.selectAgent(old.agentID)
        XCTAssertEqual(vm.version, "2.0.0")
        vm.version = "1.0.0"
        vm.draft = filledDraft(old.schema)
        let oldDraft = try XCTUnwrap(vm.draft(for: old.id))
        vm.selectAgent(other.agentID)
        XCTAssertEqual(vm.draft(for: old.id)?.id, oldDraft.id)
        var edit = oldDraft
        edit.fields["title"]!.text = "Old form completion"
        vm.setDraft(edit, for: old.id)
        XCTAssertNotEqual(vm.draft?.fields["title"]?.text, "Old form completion")
        vm.selectAgent(old.agentID)
        XCTAssertEqual(vm.version, "2.0.0")
        vm.version = "1.0.0"
        XCTAssertEqual(vm.draft?.fields["title"]?.text, "Old form completion")
    }
    func testSyntheticCatalogEntryGeneratesDraftAndExactExecutionJSONWithoutAppRegistration() async throws {
        let definition = try syntheticDefinition()
        let runner = StubLocalAgentRunner(definitions: [definition])
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        XCTAssertEqual(vm.agents.map(\.agentID), ["SyntheticNewAgent"])
        XCTAssertFalse(vm.canRun)
        vm.draft = filledDraft(definition.schema)
        let preview = vm.inputJSON
        XCTAssertTrue(vm.canRun)
        vm.run()
        await idle(vm)
        let request = await runner.requests.first
        XCTAssertEqual(request?.inputJSON, preview)
        XCTAssertEqual(request?.version, "1.0.0")
        XCTAssertEqual(vm.result?.rawOutput, "{\"ok\":true}")
    }
    func testDraftsAndVersionsSurviveSwitchesAndRemovedVersionsRequireNewSelection() async throws {
        var another = try syntheticDefinition(version: "2.0.0")
        another = .init(agentID: "AnotherAgent", name: "Another", version: another.version, schema: another.schema)
        let first = try syntheticDefinition()
        let runner = StubLocalAgentRunner(definitions: [first, another])
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.selectAgent(first.agentID); vm.draft = filledDraft(first.schema)
        let preview = vm.inputJSON
        vm.selectAgent(another.agentID)
        XCTAssertEqual(vm.version, "2.0.0")
        vm.selectAgent(first.agentID)
        XCTAssertEqual(vm.version, "1.0.0")
        XCTAssertEqual(vm.inputJSON, preview)
        await runner.setDefinitions([try syntheticDefinition(version: "3.0.0")])
        await vm.refreshProviders()
        XCTAssertEqual(vm.version, "")
        XCTAssertFalse(vm.canRun)
        XCTAssertTrue(vm.errorMessage?.contains("unavailable") == true)
    }
    func testHistoricalMetadataVersionCannotExecute() async throws {
        let runner = StubLocalAgentRunner(definitions: [try syntheticDefinition(version: "2.0.0"), try syntheticDefinition(executable: false)])
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        XCTAssertEqual(vm.version, "2.0.0")
        vm.version = "1.0.0"
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertTrue(vm.errorMessage?.contains("historical") == true)
        let count = await runner.requests.count
        XCTAssertEqual(count, 0)
    }
    func testProviderAvailabilityAndResearchRequirements() async throws {
        let definition = try syntheticDefinition(web: true)
        let runner = StubLocalAgentRunner(definitions: [definition], unavailable: [.claude])
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        XCTAssertFalse(vm.isAvailable(.claude))
        XCTAssertFalse(vm.isAvailable(.appleLocal))
        vm.selectProvider(.appleLocal)
        XCTAssertEqual(vm.provider, .codex)
        vm.draft = filledDraft(definition.schema)
        XCTAssertTrue(vm.canRun)
    }
    func testSessionSettingsRemainPerProviderAndInvalidTemperatureDoesNotRun() async throws {
        let definition = try syntheticDefinition()
        let runner = StubLocalAgentRunner(definitions: [definition])
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders(); vm.draft = filledDraft(definition.schema)
        vm.model = "model-A"; vm.sessionSettings.keepMemory = true
        vm.selectProvider(.grok); XCTAssertEqual(vm.model, "")
        vm.selectProvider(.codex); XCTAssertEqual(vm.model, "model-A")
        vm.sessionSettings.temperature = .nan
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertTrue(vm.errorMessage?.contains("Temperature") == true)
    }
    func testArrayActionsModifyNestedDraftAndSerializeWithoutCoercion() async throws {
        let definition = try syntheticDefinition()
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner(definitions: [definition]))
        await vm.refreshProviders(); vm.draft = filledDraft(definition.schema)
        let array = try XCTUnwrap(vm.draft?.fields["values"])
        vm.addArrayItem(id: array.id, schema: definition.schema.properties["values"]!)
        XCTAssertEqual(vm.draft?.fields["values"]?.items.count, 2)
        XCTAssertNil(vm.inputJSON)
        let second = try XCTUnwrap(vm.draft?.fields["values"]?.items.last)
        vm.removeArrayItem(parentID: array.id, itemID: second.id)
        XCTAssertNotNil(vm.inputJSON)
    }
    func testDuplicateRunAndCooperativeCancellation() async throws {
        let started = expectation(description: "Started")
        let definition = try syntheticDefinition()
        let runner = StubLocalAgentRunner(definitions: [definition], started: started)
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders(); vm.draft = filledDraft(definition.schema)
        vm.run(); vm.run()
        await fulfillment(of: [started], timeout: 2)
        vm.cancel()
        XCTAssertTrue(vm.isCancelling)
        XCTAssertTrue(vm.isRunning)
        await runner.release()
        await idle(vm)
        XCTAssertEqual(vm.status, "Cancelled")
        let count = await runner.requests.count
        XCTAssertEqual(count, 1)
    }
    func testFailureKeepsRawOutputAndNavigationHasNoRefineTab() async throws {
        let definition = try syntheticDefinition()
        let runner = StubLocalAgentRunner(definitions: [definition], failure: .invalidOutput(raw: "bad", reason: "Invalid"))
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders(); vm.draft = filledDraft(definition.schema)
        vm.run(); await idle(vm)
        XCTAssertEqual(vm.rawOutput, "bad")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(ContentViewModel.Tab.allCases.map(\.title), ["Studio", "Library", "LocalAgent", "Pipeline"])
    }
    private func idle(_ vm: LocalAgentViewModel) async {
        for _ in 0..<200 { if !vm.isRunning { return }; try? await Task.sleep(for: .milliseconds(5)) }
        XCTFail("Execution did not complete")
    }
}

private actor StubLocalAgentRunner: LocalAgentRunning {
    var definitions: [LocalAgentDefinition]
    var requests: [LocalAgentRequest] = []
    let unavailable: Set<LocalAgentProvider>
    let started: XCTestExpectation?
    let failure: LocalAgentError?
    var continuation: CheckedContinuation<Void, Never>?
    init(definitions: [LocalAgentDefinition], unavailable: Set<LocalAgentProvider> = [], started: XCTestExpectation? = nil, failure: LocalAgentError? = nil) {
        self.definitions = definitions; self.unavailable = unavailable; self.started = started; self.failure = failure
    }
    func catalog() async throws -> [LocalAgentDefinition] { definitions }
    func setDefinitions(_ definitions: [LocalAgentDefinition]) { self.definitions = definitions }
    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map { ($0, .init(isAvailable: !unavailable.contains($0), reason: "Test availability")) })
    }
    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        requests.append(request)
        if let started { await withCheckedContinuation { continuation = $0; started.fulfill() } }
        if let failure { throw failure }
        return .init(text: "Result", rawOutput: "{\"ok\":true}")
    }
    func release() { continuation?.resume(); continuation = nil }
}

final class TerminalLocalAgentServiceTests: XCTestCase {
    private func service(_ session: StubTerminalSession, entries: [AgentCatalogEntry]? = nil) -> TerminalLocalAgentService {
        .init(entries: entries, makeSession: { _, _ in session }, makeWorkspace: { URL(fileURLWithPath: "/unused") }, removeWorkspace: { _ in })
    }
    private func request(version: String = "1.0.0") throws -> LocalAgentRequest {
        .init(agentID: "SyntheticNewAgent", version: version, inputJSON: try payload(), provider: .codex, executable: "fake")
    }
    func testPackageDiscoveryIsTheOnlyCatalogAndHistoricalVersionsAreNotMisrouted() async throws {
        let session = StubTerminalSession(response: .success("{}"))
        let catalog = try await service(session).catalog()
        XCTAssertEqual(Set(catalog.map(\.agentID)), Set(KhabarwaaniAgent.agents.keys))
        for (id, descriptor) in KhabarwaaniAgent.agents {
            let versions = catalog.filter { $0.agentID == id }
            XCTAssertEqual(Set(versions.map(\.version)), Set(descriptor.allVersions))
            XCTAssertEqual(versions.filter(\.isExecutable).map(\.version), [descriptor.latestVersion])
        }
        let historical = catalog.filter { !$0.isExecutable }
        for entry in historical {
            let input = LocalAgentRequest(agentID: entry.agentID, version: entry.version, inputJSON: "{}", provider: .codex, executable: "fake")
            do { _ = try await service(session).run(input); XCTFail("Historical version executed current spec") }
            catch { XCTAssertTrue(error.localizedDescription.contains("not available locally")) }
        }
        let sent = await session.recorder.input
        XCTAssertEqual(sent, "")
    }
    func testSyntheticNewSpecUsesExactPreviewPayloadAndTypedOutput() async throws {
        let raw = " {\"ok\":true}\n"
        let session = StubTerminalSession(response: .success(raw))
        let input = try request()
        let result = try await service(session, entries: [syntheticEntry()]).run(input)
        XCTAssertEqual(result.rawOutput, raw)
        let sent = await session.recorder.input
        XCTAssertEqual(sent, input.inputJSON)
        XCTAssertTrue(result.metadata?.contains("Synthetic New Agent") == true)
    }
    func testInvalidOutputRetainsRawAndMissingVersionFailsBeforeSession() async throws {
        let session = StubTerminalSession(response: .success("{\"wrong\":true}"))
        do { _ = try await service(session, entries: [syntheticEntry()]).run(request()); XCTFail("Expected typed output failure") }
        catch LocalAgentError.invalidOutput(let raw, _) { XCTAssertEqual(raw, "{\"wrong\":true}") }
        do { _ = try await service(session, entries: [syntheticEntry()]).run(request(version: "9.0.0")); XCTFail("Expected missing version") }
        catch { XCTAssertTrue(error.localizedDescription.contains("not available locally")) }
    }
    func testProviderErrorsKeepDiagnosticsAndCleanup() async throws {
        let cleaned = expectation(description: "Cleaned")
        let session = StubTerminalSession(response: .failure(.operationFailed(reason: "CLI exited")))
        let service = TerminalLocalAgentService(entries: [syntheticEntry()], makeSession: { _, _ in session },
            makeWorkspace: { URL(fileURLWithPath: "/unused") }, removeWorkspace: { _ in cleaned.fulfill() },
            readDiagnostics: { _ in #"{"type":"error","message":"Sign in first"}"# })
        do { _ = try await service.run(request()); XCTFail("Expected failure") }
        catch LocalAgentError.executionFailed(let raw, let reason) {
            XCTAssertTrue(raw.contains("Sign in first")); XCTAssertTrue(reason.contains("CLI exited")); XCTAssertTrue(reason.contains("Sign in first"))
        }
        await fulfillment(of: [cleaned], timeout: 2)
    }
    func testStrictSchemaClosesNestedObjectsAndKeepsNullableFields() throws {
        let input = try XCTUnwrap(JSONString(#"{"type":"object","properties":{"nested":{"type":"object","properties":{"count":{"type":"integer"}}},"optional":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["nested"]}"#))
        let strict = try StrictLocalAgentSession.strictSchema(input)
        let value = try JSONDecoder().decode(AgentJSON.self, from: Data(strict.rawValue.utf8))
        XCTAssertEqual(value.object["additionalProperties"], .bool(false))
        XCTAssertEqual(Set(value.object["required"]!.array.compactMap(\.string)), ["nested", "optional"])
        XCTAssertEqual(value.object["properties"]?.object["nested"]?.object["additionalProperties"], .bool(false))
    }
}
private actor SessionRecorder {
    var input = ""
    func record(_ input: String) { self.input = input }
}
private final class StubTerminalSession: TerminalSessionProtocol, ManagedLocalAgentSession, Sendable {
    let configuration = TerminalAgentConfiguration(executablePath: "fake")
    var executionMetadata: [AgenticExecutionMetadata] { [] }
    let response: Result<String, AgenticError>
    let recorder = SessionRecorder()
    init(response: Result<String, AgenticError>) { self.response = response }
    func respond(to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier) async -> Result<String, AgenticError> {
        await recorder.record(input); return response
    }
    func purgeMemory() {}
}
