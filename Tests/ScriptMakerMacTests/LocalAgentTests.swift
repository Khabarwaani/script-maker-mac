import XCTest
import AgentAtom
import TerminalAgentSession
@testable import ScriptMakerMac

@MainActor
final class LocalAgentViewModelTests: XCTestCase {
    func testBlankNewsDoesNotRun() async {
        let runner = StubLocalAgentRunner()
        let vm = LocalAgentViewModel(service: runner)
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
        vm.news = "Verified facts"
        vm.provider = .claude
        vm.executableOverride = " /usr/local/bin/claude "
        vm.model = " custom-model "
        vm.userJoke = "  joke  "
        vm.run()
        await waitForIdle(vm)
        XCTAssertEqual(vm.result?.text, "Readable result")
        XCTAssertEqual(vm.rawOutput, " raw result \n")
        let request = await runner.requests.first
        XCTAssertEqual(request?.provider, .claude)
        XCTAssertEqual(request?.executable, "/usr/local/bin/claude")
        XCTAssertEqual(request?.model, "custom-model")
        XCTAssertEqual(request?.userJoke, "joke")
        XCTAssertNil(vm.errorMessage)
    }

    func testJokeToolDoesNotRequireNewsAndRejectsInvalidCounts() {
        let vm = LocalAgentViewModel(service: StubLocalAgentRunner())
        vm.tool = .shekharJoke
        XCTAssertTrue(vm.canRun)
        vm.newsCount = 0
        XCTAssertFalse(vm.canRun)
        vm.run()
        XCTAssertNotNil(vm.errorMessage)
        XCTAssertFalse(vm.isRunning)
    }

    func testFailurePreservesRawOutput() async {
        let runner = StubLocalAgentRunner(failure: .invalidOutput(raw: "broken JSON", reason: "Invalid JSON"))
        let vm = LocalAgentViewModel(service: runner)
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
    var requests: [LocalAgentRequest] = []
    let failure: LocalAgentError?
    let started: XCTestExpectation?
    let suspend: Bool
    var continuation: CheckedContinuation<Void, Never>?

    init(failure: LocalAgentError? = nil, started: XCTestExpectation? = nil, suspend: Bool = false) {
        self.failure = failure
        self.started = started
        self.suspend = suspend
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

    func release() { continuation?.resume(); continuation = nil }
}

final class TerminalLocalAgentServiceTests: XCTestCase {
    func testStorySpecRoutingAndExactRawOutput() async throws {
        let session = StubTerminalSession(response: .success(storyJSON))
        let service = makeService(session)
        let result = try await service.run(request(.threeSceneStory))
        XCTAssertEqual(result.rawOutput, storyJSON)
        XCTAssertTrue(result.text.contains("Scene 1"))
        XCTAssertTrue(result.text.contains("A title"))
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

private final class StubTerminalSession: TerminalSessionProtocol, Sendable {
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
  {"items":[{"title":"A title","scene_1":{"purpose":"Curiosity","characters":"A","setting":"Street","speech":"Speech one","speech_word_count":2},"scene_2":{"purpose":"Discussion","characters":"B","setting":"Office","speech":"Speech two","speech_word_count":2},"scene_3":{"purpose":"Reaction","characters":"C","setting":"Home","speech":"Speech three","speech_word_count":2,"joke_applied":"Joke"},"verification":{"different_concepts":true,"freshness_maintained":true,"shareability_verified":true,"notes":"Checked"}}]}

"""
