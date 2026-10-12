import XCTest
@testable import ScriptMakerMac

/// Shared canned refine output (matches the output schema).
let refineOutputJSON = """
{
    "detected_issues": [
        {
            "category": "emotion_inconsistency",
            "description": "John laughs during grave news.",
            "correction_applied": "Replaced with somber pacing."
        }
    ],
    "refined_scripts": [
        {
            "variation_index": 1,
            "script": "INT. OFFICE - DAY\\nJOHN (devastated)\\nI just lost everything.",
            "notes": "Direct emotional correction."
        },
        {
            "variation_index": 2,
            "script": "INT. OFFICE - DAY\\nJOHN (stunned)\\nI... lost everything.",
            "notes": "Nuanced reaction emphasizing shock."
        }
    ]
}
"""

final class MockRefineTransport: RefineTransport, @unchecked Sendable {
    var lastURL: URL?
    var lastBody: Data?
    var calls = 0
    var stub: (data: Data, statusCode: Int) = (Data(), 200)
    var stubError: Error?

    var streamEvents: [RefineStreamEvent] = []
    var streamError: Error?

    func postStream(to url: URL, body: Data) -> AsyncThrowingStream<RefineStreamEvent, Error> {
        calls += 1
        lastURL = url
        lastBody = body
        let events = streamEvents
        let err = streamError
        return AsyncThrowingStream { continuation in
            if let err {
                continuation.finish(throwing: err)
                return
            }
            for event in events { continuation.yield(event) }
            continuation.finish()
        }
    }

    func post(to url: URL, body: Data) async throws -> (data: Data, statusCode: Int) {
        calls += 1
        lastURL = url
        lastBody = body
        if let stubError { throw stubError }
        return stub
    }
}

final class RefineServiceTests: XCTestCase {
    private func makeInput() -> RefineInput {
        RefineInput(
            script: "INT. OFFICE - DAY",
            outputCount: 3,
            issuesFound: [RefineKnownIssue(category: .emotionInconsistency,
                                          description: "Laughing at bad news.")],
            correctionFocus: [.textCorrection, .emotionDetection]
        )
    }

    private func jsonBody(_ mock: MockRefineTransport) throws -> [String: Any] {
        let body = try XCTUnwrap(mock.lastBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    }

    func testPostsToExecutePath() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        _ = try await RefineService(transport: mock)
            .refine(baseURL: base, provider: .antigravity, input: makeInput())
        XCTAssertEqual(mock.lastURL?.absoluteString, "http://127.0.0.1:8080/execute")
    }

    func testExecuteURLAppendsPath() throws {
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        XCTAssertEqual(RefineService.executeURL(baseURL: base).absoluteString,
                       "http://127.0.0.1:8080/execute")
    }

    func testExecuteURLDoesNotDoublePath() throws {
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/execute"))
        XCTAssertEqual(RefineService.executeURL(baseURL: base).absoluteString,
                       "http://127.0.0.1:8080/execute")
    }

    func testEnvelopeKeys() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        _ = try await RefineService(transport: mock)
            .refine(baseURL: base, provider: .antigravity, input: makeInput())

        let body = try jsonBody(mock)
        XCTAssertEqual(body["agent_id"] as? String, "ScriptRefiner")
        XCTAssertNil(body["version"])
        XCTAssertEqual(body["provider"] as? String, "antigravity")
        let input = try XCTUnwrap(body["input"] as? [String: Any])
        XCTAssertEqual(input["script"] as? String, "INT. OFFICE - DAY")
        XCTAssertEqual(input["output_count"] as? Int, 3)
        let issues = try XCTUnwrap(input["issues_found"] as? [[String: Any]])
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0]["category"] as? String, "emotion_inconsistency")
        let focus = try XCTUnwrap(input["correction_focus"] as? [String])
        XCTAssertTrue(focus.contains("text_correction"))
        XCTAssertTrue(focus.contains("emotion_detection"))
    }

    func testOmitsEmptyOptionals() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        let bare = RefineInput(script: "x", outputCount: 1, issuesFound: nil, correctionFocus: [])
        _ = try await RefineService(transport: mock)
            .refine(baseURL: base, provider: .antigravity, input: bare)

        let body = try jsonBody(mock)
        let input = try XCTUnwrap(body["input"] as? [String: Any])
        XCTAssertNil(input["issues_found"])
        XCTAssertNil(input["correction_focus"])
    }

    func testDecodesTopLevelResponse() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        let output = try await RefineService(transport: mock)
            .refine(baseURL: base, provider: .antigravity, input: makeInput()).output
        XCTAssertEqual(output.detectedIssues.count, 1)
        XCTAssertEqual(output.detectedIssues[0].category, .emotionInconsistency)
        XCTAssertEqual(output.refinedScripts.count, 2)
        XCTAssertEqual(output.refinedScripts[0].variationIndex, 1)
        XCTAssertTrue(output.refinedScripts[0].script.contains("JOHN (devastated)"))
    }

    func testDecodesWrappedResponse() async throws {
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        for wrapper in ["output", "result", "data"] {
            let mock = MockRefineTransport()
            mock.stub = (Data("{\"\(wrapper)\":\(refineOutputJSON)}".utf8), 200)
            let output = try await RefineService(transport: mock)
                .refine(baseURL: base, provider: .antigravity, input: makeInput()).output
            XCTAssertEqual(output.refinedScripts.count, 2, "wrapper: \(wrapper)")
        }
    }

    func testRefineResultCarriesWireDetails() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data(refineOutputJSON.utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        let result = try await RefineService(transport: mock)
            .refine(baseURL: base, provider: .antigravity, input: makeInput())
        XCTAssertEqual(result.requestURL.absoluteString, "http://127.0.0.1:8080/execute")
        XCTAssertEqual(result.statusCode, 200)
        XCTAssertTrue(String(data: result.requestBody, encoding: .utf8)?.contains("ScriptRefiner") == true)
        XCTAssertEqual(result.responseBody, Data(refineOutputJSON.utf8))
        XCTAssertEqual(result.output.refinedScripts.count, 2)
    }

    func testServerErrorEnvelopeParsed() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data("""
            {"error": {"code": "unsupported_provider",
                       "message": "The selected provider is not configured or supported."}}
            """.utf8), 400)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        do {
            _ = try await RefineService(transport: mock)
                .refine(baseURL: base, provider: .antigravity, input: makeInput())
            XCTFail("expected RefineAPIError.serverError")
        } catch RefineAPIError.serverError(let code, let message, let status) {
            XCTAssertEqual(code, "unsupported_provider")
            XCTAssertTrue(message.contains("not configured or supported"))
            XCTAssertEqual(status, 400)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStreamURLHasStatusQuery() async throws {
        let mock = MockRefineTransport()
        mock.streamEvents = [
            RefineStreamEvent(name: "result", data: refineOutputJSON)
        ]
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        var items: [RefineStreamItem] = []
        for try await item in RefineService(transport: mock)
            .refineStream(baseURL: base, provider: .antigravity, input: makeInput()) {
            items.append(item)
        }
        XCTAssertTrue(mock.lastURL?.absoluteString.contains("execute?status=true") == true)
        XCTAssertEqual(items.count, 1)
        if case .result(let result) = items[0] {
            XCTAssertEqual(result.output.refinedScripts.count, 2)
        } else {
            XCTFail("expected .result")
        }
    }

    func testStreamYieldsProgressThenResult() async throws {
        let mock = MockRefineTransport()
        mock.streamEvents = [
            RefineStreamEvent(name: "progress", data: "analyzing script"),
            RefineStreamEvent(name: "progress", data: "generating variations"),
            RefineStreamEvent(name: "result", data: refineOutputJSON),
        ]
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        var progress: [String] = []
        var results = 0
        for try await item in RefineService(transport: mock)
            .refineStream(baseURL: base, provider: .antigravity, input: makeInput()) {
            switch item {
            case .progress(_, let data): progress.append(data)
            case .result: results += 1
            }
        }
        XCTAssertEqual(progress, ["analyzing script", "generating variations"])
        XCTAssertEqual(results, 1)
    }

    func testStreamWithoutResultThrows() async throws {
        let mock = MockRefineTransport()
        mock.streamEvents = [RefineStreamEvent(name: "progress", data: "still working")]
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        do {
            for try await _ in RefineService(transport: mock)
                .refineStream(baseURL: base, provider: .antigravity, input: makeInput()) {}
            XCTFail("expected malformed error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("without a result"))
        }
    }

    func testNon2xxThrowsServerError() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data("boom".utf8), 500)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        do {
            _ = try await RefineService(transport: mock)
                .refine(baseURL: base, provider: .antigravity, input: makeInput())
            XCTFail("expected APIError.server")
        } catch APIError.server(let code, _) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testBadJSONThrowsMalformed() async throws {
        let mock = MockRefineTransport()
        mock.stub = (Data("not json".utf8), 200)
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        do {
            _ = try await RefineService(transport: mock)
                .refine(baseURL: base, provider: .antigravity, input: makeInput())
            XCTFail("expected APIError.malformed")
        } catch APIError.malformed {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testTransportErrorPropagates() async throws {
        let mock = MockRefineTransport()
        mock.stubError = APIError.transport("no route to host")
        let base = try XCTUnwrap(URL(string: "http://127.0.0.1:8080/"))
        do {
            _ = try await RefineService(transport: mock)
                .refine(baseURL: base, provider: .antigravity, input: makeInput())
            XCTFail("expected APIError.transport")
        } catch APIError.transport {
            // expected
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}
