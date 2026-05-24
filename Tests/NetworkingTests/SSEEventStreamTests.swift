import Foundation
import Testing
@testable import Networking

@Suite("SSEEventStream")
struct SSEEventStreamTests {

    @Test func parsesSingleLFFramedEvent() async throws {
        let events = try await collect("event: message_start\ndata: {\"type\":\"start\"}\n\n")
        #expect(events.count == 1)
        #expect(events[0].event == "message_start")
        #expect(String(data: events[0].data, encoding: .utf8) == "{\"type\":\"start\"}")
    }

    @Test func parsesCRLFFramedEvent() async throws {
        let events = try await collect("event: ping\r\ndata: hi\r\n\r\n")
        #expect(events.count == 1)
        #expect(events[0].event == "ping")
        #expect(String(data: events[0].data, encoding: .utf8) == "hi")
    }

    @Test func joinsMultilineData() async throws {
        let events = try await collect("event: chunk\ndata: line1\ndata: line2\ndata: line3\n\n")
        #expect(events.count == 1)
        #expect(String(data: events[0].data, encoding: .utf8) == "line1\nline2\nline3")
    }

    @Test func ignoresCommentLines() async throws {
        let events = try await collect(": comment\nevent: ping\ndata: ok\n\n")
        #expect(events.count == 1)
        #expect(events[0].event == "ping")
    }

    @Test func emitsPingEventsForConsumer() async throws {
        let events = try await collect("event: ping\ndata: {}\n\nevent: message_stop\ndata: {}\n\n")
        #expect(events.map(\.event) == ["ping", "message_stop"])
    }

    @Test func unknownEventNamesPassThrough() async throws {
        let events = try await collect("event: weird\ndata: foo\n\n")
        #expect(events.count == 1)
        #expect(events[0].event == "weird")
    }

    @Test func propagatesUpstreamError() async {
        struct Boom: Error {}
        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            continuation.finish(throwing: Boom())
        }
        var caught: Error?
        do {
            for try await _ in sseEventStream(from: bytes) {}
        } catch {
            caught = error
        }
        #expect(caught is Boom)
    }

    @Test func cancellingConsumerCancelsParser() async {
        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            Task {
                for _ in 0..<10_000 {
                    if Task.isCancelled {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                    continuation.yield(UInt8(ascii: "."))
                    try? await Task.sleep(for: .milliseconds(5))
                }
                continuation.finish()
            }
        }
        let task = Task<Int, Error> {
            var count = 0
            for try await _ in sseEventStream(from: bytes) { count += 1 }
            return count
        }
        try? await Task.sleep(for: .milliseconds(20))
        task.cancel()
        _ = try? await task.value
    }

    private func collect(_ raw: String) async throws -> [SSEEvent] {
        let bytes = AsyncThrowingStream<UInt8, Error> { continuation in
            for byte in Data(raw.utf8) { continuation.yield(byte) }
            continuation.finish()
        }
        var events: [SSEEvent] = []
        for try await event in sseEventStream(from: bytes) {
            events.append(event)
        }
        return events
    }
}
