@testable import ScriptMakerMac
import XCTest

/// The stream parser must yield events as lines arrive — never buffer
/// everything to stream end. These tests drive the parser line by line.
final class HTTPRefineTransportTests: XCTestCase {

    private func collect(_ lines: [String]) async throws -> [RefineStreamEvent] {
        var events: [RefineStreamEvent] = []
        let input = AsyncStream<String> { cont in
            for line in lines { cont.yield(line) }
            cont.finish()
        }
        let stream = AsyncThrowingStream<RefineStreamEvent, Error> { continuation in
            Task {
                try? await HTTPRefineTransport.yieldLiveEvents(from: input, to: continuation)
                continuation.finish()
            }
        }
        for try await event in stream { events.append(event) }
        return events
    }

    /// Producer/consumer handshake: each line is sent only after the
    /// previous event was received — proves events are not buffered to
    /// stream end. (Would deadlock under the old end-buffered parser.)
    func testDataLinesYieldLive() async throws {
        let (lineStream, lineCont) = AsyncStream<String>.makeStream()
        let (ackStream, ackCont) = AsyncStream<Void>.makeStream()

        Task {
            var acks = ackStream.makeAsyncIterator()
            lineCont.yield(#"data: {"a": 1}"#)
            lineCont.yield(#"data: {"b": 2}"#) // flushes the {"a": 1} event
            await acks.next()                  // event a arrived before line c
            lineCont.yield(#"data: {"c": 3}"#) // flushes the {"b": 2} event
            await acks.next()                  // event b arrived before finish
            lineCont.finish()
            ackCont.finish()
        }

        var received: [String] = []
        let stream = AsyncThrowingStream<RefineStreamEvent, Error> { continuation in
            Task {
                try? await HTTPRefineTransport.yieldLiveEvents(from: lineStream, to: continuation)
                continuation.finish()
            }
        }
        for try await event in stream {
            received.append(event.data)
            ackCont.yield(())
        }
        XCTAssertEqual(received, [#"{"a": 1}"#, #"{"b": 2}"#, #"{"c": 3}"#])
    }

    func testTrueSSECoalescesAtBlankLine() async throws {
        let events = try await collect([
            "event: progress",
            #"data: {"a": 1}"#,
            "",
            #"data: {"b": 2}"#,
            "",
        ])
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].name, "progress")
        XCTAssertEqual(events[0].data, #"{"a": 1}"#)
        XCTAssertEqual(events[1].name, "message")
        XCTAssertEqual(events[1].data, #"{"b": 2}"#)
    }

    func testRawJSONLinesYieldAsLineEvents() async throws {
        let events = try await collect([#"{"a": 1}"#, #"{"b": 2}"#])
        XCTAssertEqual(events.map(\.name), ["line-0", "line-1"])
        XCTAssertEqual(events.map(\.data), [#"{"a": 1}"#, #"{"b": 2}"#])
    }

    func testSkipsSSEComments() async throws {
        let events = try await collect([": keepalive", "", #"data: {"a": 1}"#, ""])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, #"{"a": 1}"#)
    }

    func testPrettyPrintedDataBlockStillCoalesces() async throws {
        // Fragments don't parse as complete JSON, so they accumulate
        // until the blank line — no regression for multi-line payloads.
        let events = try await collect(["data: {", #"data: "a": 1"#, "data: }", ""])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, "{\n\"a\": 1\n}")
    }

    func testSingleBlobYieldsOneEvent() async throws {
        let events = try await collect([#"{"a": 1, "b": 2}"#])
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].data, #"{"a": 1, "b": 2}"#)
    }
}
