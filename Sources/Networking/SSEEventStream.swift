import Foundation

public struct SSEEvent: Sendable, Equatable {
    public let event: String
    public let data: Data

    public init(event: String, data: Data) {
        self.event = event
        self.data = data
    }
}

public func sseEventStream(
    from bytes: AsyncThrowingStream<UInt8, Error>
) -> AsyncThrowingStream<SSEEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            var buffer = [UInt8]()
            var eventName: String?
            var dataChunks: [String] = []

            func dispatch() {
                defer {
                    eventName = nil
                    dataChunks = []
                }
                guard eventName != nil || !dataChunks.isEmpty else { return }
                let joined = dataChunks.joined(separator: "\n")
                let payload = Data(joined.utf8)
                continuation.yield(SSEEvent(event: eventName ?? "message", data: payload))
            }

            func processLine(_ line: String) {
                if line.isEmpty {
                    dispatch()
                    return
                }
                if line.hasPrefix(":") { return }
                if let colon = line.firstIndex(of: ":") {
                    let field = String(line[..<colon])
                    var value = String(line[line.index(after: colon)...])
                    if value.hasPrefix(" ") { value.removeFirst() }
                    switch field {
                    case "event":
                        eventName = value
                    case "data":
                        dataChunks.append(value)
                    default:
                        break
                    }
                } else {
                    // field-only line with no colon; treat as field name with empty value
                    if line == "data" { dataChunks.append("") }
                }
            }

            do {
                for try await byte in bytes {
                    if Task.isCancelled { throw CancellationError() }
                    if byte == 0x0A { // LF
                        var lineBytes = buffer
                        if lineBytes.last == 0x0D { lineBytes.removeLast() } // strip CR
                        let line = String(decoding: lineBytes, as: UTF8.self)
                        buffer.removeAll(keepingCapacity: true)
                        processLine(line)
                    } else {
                        buffer.append(byte)
                    }
                }
                if !buffer.isEmpty {
                    var tail = buffer
                    if tail.last == 0x0D { tail.removeLast() }
                    let line = String(decoding: tail, as: UTF8.self)
                    processLine(line)
                }
                dispatch()
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
