import XCTest
import AgentAtom
import TerminalAgentSession
@testable import ScriptMakerMac

@MainActor
final class LocalAgentViewModelTests: XCTestCase {
    func testVersionSelectionFollowsToolAndExecutionSource() async {
        let local = StubLocalAgentRunner()
        let server = StubLocalAgentRunner(storyVersions: ["1.0.0", "2.0.0", "2.1.0-beta"])
        let vm = LocalAgentViewModel(service: local, serverService: server)
        await vm.refreshProviders()
        XCTAssertEqual(vm.versions, ["2.0.0"])
        XCTAssertEqual(vm.version, "2.0.0")
        vm.executionSource = .server
        XCTAssertFalse(vm.canRun)
        await vm.refreshProviders()
        XCTAssertEqual(vm.versions, ["2.0.0", "1.0.0", "2.1.0-beta"])
        vm.version = "1.0.0"
        vm.news = "Verified facts"
        vm.run()
        await waitForIdle(vm)
        let executed = await server.requests.first
        XCTAssertEqual(executed?.version, "1.0.0")
        let localCount = await local.requests.count
        XCTAssertEqual(localCount, 0)
        vm.selectTool(.shekharJoke)
        XCTAssertEqual(vm.version, "1.0.0")
        vm.selectTool(.threeSceneStory)
        XCTAssertEqual(vm.version, "1.0.0")
        await server.setStoryVersions(["2.0.0"])
        await vm.refreshProviders()
        XCTAssertEqual(vm.version, "")
        XCTAssertFalse(vm.canRun)
        XCTAssertTrue(vm.errorMessage?.contains("unavailable") == true)
        vm.executionSource = .local
        await vm.refreshProviders()
        XCTAssertEqual(vm.version, "2.0.0")
    }

    func testStoryCountLimitMatchesNewContract() async {
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner())
        await vm.refreshProviders()
        vm.news = "News"
        vm.outputCount = 6
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertTrue(vm.errorMessage?.contains("1 and 5") == true)
    }
    func testUnavailableProviderCannotRunAndRefreshSelectsAnAvailableProvider() async {
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner(unavailable: [.claude, .appleLocal]))
        await vm.refreshProviders()
        vm.news = "News"
        XCTAssertFalse(vm.isAvailable(.claude))
        vm.selectProvider(.claude)
        XCTAssertEqual(vm.provider, .codex)
        vm.provider = .claude
        vm.run()
        XCTAssertFalse(vm.isRunning)
        XCTAssertFalse(vm.canRun)
        XCTAssertTrue(vm.errorMessage?.contains("not installed") == true)
        await vm.refreshProviders()
        XCTAssertEqual(vm.provider, .codex)
    }

    func testOnDeviceProviderSelectsStoryAndPassesTemperature() async {
        let runner = StubLocalAgentRunner()
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.tool = .shekharJoke
        vm.provider = .appleLocal
        XCTAssertEqual(vm.tool, .threeSceneStory)
        vm.news = "Local facts"
        vm.sessionSettings.temperature = 0.4
        vm.run()
        await waitForIdle(vm)
        let request = await runner.requests.first
        XCTAssertEqual(request?.provider, .appleLocal)
        XCTAssertEqual(request?.session.temperature, 0.4)
        XCTAssertNotNil(vm.result)
    }
    func testBlankNewsDoesNotRun() async {
        let runner = StubLocalAgentRunner()
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.news = " \n "
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertNotNil(vm.errorMessage)
        let count = await runner.requests.count
        XCTAssertEqual(count, 0)
    }

    func testSuccessAndProviderConfiguration() async {
        let runner = StubLocalAgentRunner()
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.news = "Verified facts"
        vm.provider = .claude

        vm.model = " custom-model "
        vm.userJoke = "  joke  "
        vm.run()
        await waitForIdle(vm)
        XCTAssertEqual(vm.result?.text, "Readable result")
        XCTAssertEqual(vm.rawOutput, " raw result \n")
        let request = await runner.requests.first
        XCTAssertEqual(request?.provider, .claude)
        XCTAssertEqual(request?.executable, "claude")
        XCTAssertEqual(request?.model, "custom-model")
        XCTAssertEqual(request?.userJoke, "joke")
        XCTAssertNil(vm.errorMessage)
    }

    func testJokeToolDoesNotRequireNewsAndRejectsInvalidCounts() async {
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner())
        await vm.refreshProviders()
        vm.tool = .shekharJoke
        XCTAssertTrue(vm.canRun)
        vm.newsCount = 0
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isRunning)
    }

    func testSessionSettingsAreSeparatePerProviderAndPassedToRunner() async {
        let runner = StubLocalAgentRunner()
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.tool = .shekharJoke
        vm.model = "codex-model"
        vm.sessionSettings.persistence = .persistentStdio
        vm.sessionSettings.keepMemory = true
        vm.provider = .grok
        XCTAssertEqual(vm.model, "")
        vm.model = "grok-model"
        vm.provider = .codex
        XCTAssertEqual(vm.model, "codex-model")
        vm.run()
        await waitForIdle(vm)
        let request = await runner.requests.first
        XCTAssertEqual(request?.session.persistence, .persistentStdio)
        XCTAssertEqual(request?.session.keepMemory, true)
    }

    func testInvalidTemperatureRejected() async {
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner())
        await vm.refreshProviders()
        vm.tool = .shekharJoke
        vm.sessionSettings.temperature = .nan
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertTrue(vm.errorMessage?.contains("Temperature") == true)
    }

    func testFailurePreservesRawOutput() async {
        let runner = StubLocalAgentRunner(failure: .invalidOutput(raw: "broken JSON", reason: "Invalid JSON"))
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.news = "News"
        vm.run()
        await waitForIdle(vm)
        XCTAssertNil(vm.result)
        XCTAssertEqual(vm.rawOutput, "broken JSON")
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertEqual(vm.status, "Failed")
    }

    func testCancellationSuppressesLateResultAndPreventsDuplicateRuns() async {
        let started = expectation(description: "Started")
        let runner = StubLocalAgentRunner(started: started, suspend: true)
        let vm = LocalAgentViewModel(service: runner)
        await vm.refreshProviders()
        vm.news = "News"
        vm.run()
        vm.run()
        await fulfillment(of: [started], timeout: 2)
        vm.cancel()
        XCTAssertTrue(vm.isCancelling)
        XCTAssertFalse(vm.canRun)
        await runner.release()
        await waitForIdle(vm)
        let count = await runner.requests.count
        XCTAssertEqual(count, 1)
        XCTAssertEqual(vm.status, "Cancelled")
        XCTAssertNil(vm.result)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.canRun)
    }

    private func waitForIdle(_ vm: LocalAgentViewModel) async {
        for _ in 0..<200 where vm.isRunning {
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(vm.isRunning, "Agent did not finish")
    }
}

private actor StubLocalAgentRunner: LocalAgentRunning {
    var storyVersions: [String]
    var requests: [LocalAgentRequest] = []
    let failure: LocalAgentError?
    let started: XCTestExpectation?
    let suspend: Bool
    let unavailable: Set<LocalAgentProvider>
    var continuation: CheckedContinuation<Void, Never>?

    init(failure: LocalAgentError? = nil, started: XCTestExpectation? = nil, suspend: Bool = false, unavailable: Set<LocalAgentProvider> = [], storyVersions: [String] = ["2.0.0"]) {
        self.storyVersions = storyVersions
        self.failure = failure
        self.started = started
        self.suspend = suspend
        self.unavailable = unavailable
    }

    func run(_ request: LocalAgentRequest) async throws -> LocalAgentResult {
        requests.append(request)
        if suspend {
            await withCheckedContinuation {
                continuation = $0
                started?.fulfill()
            }
        }
        if let failure { throw failure }
        return LocalAgentResult(text: "Readable result", rawOutput: " raw result \n")
    }

    func availability() async -> [LocalAgentProvider: LocalAgentAvailability] {
        Dictionary(uniqueKeysWithValues: LocalAgentProvider.allCases.map {
            ($0, LocalAgentAvailability(isAvailable: !unavailable.contains($0), reason: unavailable.contains($0) ? "CLI not installed" : "Test provider"))
        })
    }

    func versions() async throws -> [LocalAgentTool: [String]] {
        [.threeSceneStory: storyVersions, .shekharJoke: ["1.0.0"]]
    }
    func setStoryVersions(_ versions: [String]) { storyVersions = versions }

    func release() { continuation?.resume(); continuation = nil }
}

final class TerminalLocalAgentServiceTests: XCTestCase {
    func testStrictSchemaClosesNestedObjectsAndKeepsNullableFields() throws {
        let input = try XCTUnwrap(JSONString("""
        {"type":"object","properties":{"nested":{"type":"object","properties":{"count":{"type":"integer"}}},"optional":{"anyOf":[{"type":"string"},{"type":"null"}]}},"required":["nested"]}
        """))
        let strict = try StrictLocalAgentSession.strictSchema(input)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(strict.rawValue.utf8)) as? [String: Any])
        XCTAssertEqual(object["additionalProperties"] as? Bool, false)
        XCTAssertEqual(object["required"] as? [String], ["nested", "optional"])
        let properties = try XCTUnwrap(object["properties"] as? [String: [String: Any]])
        XCTAssertEqual(properties["nested"]?["additionalProperties"] as? Bool, false)
        XCTAssertEqual(properties["nested"]?["required"] as? [String], ["count"])
        let nullable = try XCTUnwrap(properties["optional"]?["anyOf"] as? [[String: String]])
        XCTAssertTrue(nullable.contains(["type": "null"]))
    }

    func testCLIStdoutDiagnosticsAreRetainedOnFailure() async {
        let session = StubTerminalSession(response: .failure(.operationFailed(reason: "CLI exited")))
        let service = TerminalLocalAgentService(makeSession: { _, _ in session },
                                               makeWorkspace: { URL(fileURLWithPath: "/unused") },
                                               removeWorkspace: { _ in },
                                               readDiagnostics: { _ in "{\"type\":\"error\",\"message\":\"Schema rejected\"}" })
        do {
            _ = try await service.run(request(.threeSceneStory))
            XCTFail("Expected failure")
        } catch LocalAgentError.executionFailed(let raw, let reason) {
            XCTAssertTrue(raw.contains("Schema rejected"))
            XCTAssertTrue(reason.contains("CLI exited"))
            XCTAssertTrue(reason.contains("Schema rejected"))
            XCTAssertFalse(reason.contains("\"type\""))
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testStorySpecRoutingAndExactRawOutput() async throws {
        let session = StubTerminalSession(response: .success(storyJSON))
        let service = makeService(session)
        let result = try await service.run(request(.threeSceneStory))
        XCTAssertEqual(result.rawOutput, storyJSON)
        XCTAssertTrue(result.text.contains("Scene 1"))
        XCTAssertTrue(result.text.contains("A title"))
        XCTAssertTrue(result.text.contains("A: Speech one"))
        XCTAssertTrue(result.text.contains("Passed: false"))
        XCTAssertTrue(result.text.contains("Words: 2"))
        let input = await session.recorder.input
        XCTAssertTrue(input.contains("Verified news"))
        XCTAssertTrue(input.contains("user_joke"))
        let instructions = await session.recorder.instructions
        XCTAssertTrue(instructions.contains("ThreeSceneStoryCreator"))
    }

    func testJokeSpecRouting() async throws {
        let raw = """
        {"items":[{"title":"Headline","date":"Today","link":"https://example.com","category":"Trending","joke1":"Short","joke2":"Long","script":"Script"}]}
        """
        let session = StubTerminalSession(response: .success(raw))
        let result = try await makeService(session).run(request(.shekharJoke))
        XCTAssertEqual(result.rawOutput, raw)
        XCTAssertTrue(result.text.contains("Short"))
        let input = await session.recorder.input
        XCTAssertTrue(input.contains("news_count"))
        XCTAssertFalse(input.contains("Verified news"))
    }

    func testLocalVersionIsDerivedFromPackageAndRejectsUnavailableVersionBeforeSession() async throws {
        let session = StubTerminalSession(response: .success(storyJSON))
        let service = makeService(session)
        let versions = try await service.versions()
        XCTAssertEqual(versions[.threeSceneStory], ["2.0.0"])
        var input = request(.threeSceneStory)
        input.version = "1.0.0"
        do {
            _ = try await service.run(input)
            XCTFail("Expected unavailable version")
        } catch { XCTAssertTrue(error.localizedDescription.contains("not available locally")) }
        let sent = await session.recorder.input
        XCTAssertTrue(sent.isEmpty)
    }

    func testMalformedOutputRetained() async {
        do {
            _ = try await makeService(StubTerminalSession(response: .success("invalid"))).run(request(.threeSceneStory))
            XCTFail("Expected decoding failure")
        } catch LocalAgentError.invalidOutput(let raw, _) {
            XCTAssertEqual(raw, "invalid")
        } catch { XCTFail("Unexpected error: \(error)") }
    }

    func testCLIErrorSurfaces() async {
        do {
            _ = try await makeService(StubTerminalSession(response: .failure(.operationFailed(reason: "Sign in first")))).run(request(.threeSceneStory))
            XCTFail("Expected CLI error")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Sign in first")) }
    }

    func testMissingExecutableAndCleanup() async {
        let cleaned = expectation(description: "Workspace cleaned")
        let service = TerminalLocalAgentService(
            makeSession: { request, _ in throw LocalAgentError.unavailable(request.executable) },
            makeWorkspace: { URL(fileURLWithPath: "/unused-test-directory") },
            removeWorkspace: { _ in cleaned.fulfill() })
        do {
            _ = try await service.run(request(.threeSceneStory))
            XCTFail("Expected unavailable CLI")
        } catch { XCTAssertTrue(error.localizedDescription.contains("Could not find")) }
        await fulfillment(of: [cleaned], timeout: 2)
    }

    private func request(_ tool: LocalAgentTool) -> LocalAgentRequest {
        LocalAgentRequest(tool: tool, provider: .codex, executable: "codex", model: nil,
                          news: "Verified news", userJoke: "Joke", outputCount: 1, newsCount: 3, jokesPerCategory: 2)
    }

    private func makeService(_ session: StubTerminalSession) -> TerminalLocalAgentService {
        TerminalLocalAgentService(makeSession: { _, _ in session },
                                  makeWorkspace: { URL(fileURLWithPath: "/unused-test-directory") },
                                  removeWorkspace: { _ in })
    }
}

private actor SessionRecorder {
    var input = ""
    var instructions = ""
    func record(input: String, instructions: String) { self.input = input; self.instructions = instructions }
}

private final class StubTerminalSession: TerminalSessionProtocol, ManagedLocalAgentSession, Sendable {
    let configuration = TerminalAgentConfiguration(executablePath: "fake")
    var executionMetadata: [AgenticExecutionMetadata] { [] }
    let response: Result<String, AgenticError>
    let recorder = SessionRecorder()
    init(response: Result<String, AgenticError>) { self.response = response }
    func respond(to input: String, instructions: String, schema: JSONString, for operation: ObjectIdentifier) async -> Result<String, AgenticError> {
        await recorder.record(input: input, instructions: instructions)
        return response
    }
}

private let storyJSON = """
  {"items":[{"title":"A title","scenes":[
    {"title":"Curiosity","goal":"Hook","location":"Street","dialogues":[{"speaker":"A","dialogue":"Speech one"}],"words_count":2,"verification":{"passed":false,"dialogue_sensible":false,"different_concepts":true,"freshness_maintained":true,"notes":"Human review"}},
    {"title":"Discussion","goal":"News","location":"Office","dialogues":[{"speaker":"B","dialogue":"Speech two"}],"words_count":2,"verification":{"passed":true,"dialogue_sensible":true,"different_concepts":true,"freshness_maintained":true,"notes":"Checked"}},
    {"title":"Reaction","goal":"Share","location":"Home","dialogues":[{"speaker":"C","dialogue":"Speech three"}],"words_count":2,"verification":{"passed":true,"dialogue_sensible":true,"different_concepts":true,"freshness_maintained":true,"notes":"Checked"}}
  ]}]}

"""

final class ServerLocalAgentServiceTests: XCTestCase {
    private func service(versions: [String] = ["2.0.0"]) -> ServerLocalAgentService {
        AgentVersionURLProtocol.versions = versions
        AgentVersionURLProtocol.requests = []
        AgentVersionURLProtocol.failure = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AgentVersionURLProtocol.self]
        return ServerLocalAgentService(httpClient: HTTPClient(session: URLSession(configuration: configuration)),
            serverURL: { URL(string: "http://agent.test/api")! })
    }

    private var request: LocalAgentRequest {
        LocalAgentRequest(tool: .threeSceneStory, provider: .codex, executable: "codex", model: nil,
            news: "Verified news", userJoke: "User joke", outputCount: 1, newsCount: 3, jokesPerCategory: 2,
            version: "2.0.0")
    }

    func testServerCatalogAvailabilityAndExplicitVersionPayload() async throws {
        let server = service(versions: ["1.0.0", "2.0.0"])
        let versions = try await server.versions()
        XCTAssertEqual(versions[.threeSceneStory], ["1.0.0", "2.0.0"])
        XCTAssertEqual(versions[.shekharJoke], [])
        let availability = await server.availability()
        XCTAssertEqual(availability[.codex]?.isAvailable, true)
        XCTAssertEqual(availability[.claude]?.isAvailable, false)
        XCTAssertEqual(availability[.appleLocal]?.isAvailable, false)
        let result = try await server.run(request)
        XCTAssertEqual(result.rawOutput, storyJSON)
        XCTAssertTrue(result.text.contains("A: Speech one"))
        let executed = try XCTUnwrap(AgentVersionURLProtocol.requests.first { $0.url?.path == "/api/execute" })
        XCTAssertEqual(executed.httpMethod, "POST")
        XCTAssertEqual(executed.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let data = try XCTUnwrap(executed.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["agent_id"] as? String, "ThreeSceneStoryCreator")
        XCTAssertEqual(json["version"] as? String, "2.0.0")
        XCTAssertEqual(json["provider"] as? String, "codex")
        let input = try XCTUnwrap(json["input"] as? [String: Any])
        XCTAssertEqual(input["news"] as? String, "Verified news")
        XCTAssertEqual(input["user_joke"] as? String, "User joke")
        XCTAssertNil(input["news_count"])
    }

    func testUnavailableVersionNeverExecutesOrFallsBack() async throws {
        let server = service()
        var input = request
        input.version = "1.0.0"
        do {
            _ = try await server.run(input)
            XCTFail("Expected unavailable version")
        } catch { XCTAssertTrue(error.localizedDescription.contains("available server agent version")) }
        XCTAssertFalse(AgentVersionURLProtocol.requests.contains { $0.httpMethod == "POST" })
    }

    func testServerErrorRetainsExactDiagnostics() async throws {
        let server = service()
        AgentVersionURLProtocol.failure = true
        do {
            _ = try await server.run(request)
            XCTFail("Expected server error")
        } catch LocalAgentError.executionFailed(let raw, let reason) {
            XCTAssertTrue(raw.contains("provider_unavailable"))
            XCTAssertEqual(reason, "provider_unavailable: Sign in on server")
        } catch { XCTFail("Unexpected error: \(error)") }
    }
}

private final class AgentVersionURLProtocol: URLProtocol {
    static var versions = ["2.0.0"]
    static var requests: [URLRequest] = []
    static var failure = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var captured = request
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            captured.httpBody = body
        }
        Self.requests.append(captured)
        let data: Data
        var status = 200
        switch request.url!.lastPathComponent {
        case "agents":
            data = try! JSONSerialization.data(withJSONObject: ["agents": [["id": "ThreeSceneStoryCreator", "name": "Story", "versions": Self.versions]]])
        case "status":
            data = Data(#"{"providers":[{"id":"codex","available":true,"readiness":"ready"},{"id":"claude","available":false,"readiness":"unavailable"}]}"#.utf8)
        default:
            status = Self.failure ? 422 : 200
            data = Data((Self.failure ? #"{"error":{"code":"provider_unavailable","message":"Sign in on server"}}"# : storyJSON).utf8)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
