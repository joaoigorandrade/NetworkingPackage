import Foundation
import Networking
import Synchronization

/// A fake socket transport. Tests push inbound frames with `emit(_:)` and
/// simulate transport failures with `fail(_:)`.
public actor MockWebSocketTask: WebSocketTaskHandle {
    private var resumed = false
    private var closed = false
    private var storedCloseCode: URLSessionWebSocketTask.CloseCode = .invalid
    private var storedCloseReason: String?
    private var outbound: [WebSocketMessage] = []
    private var inbound: [WebSocketMessage] = []
    private var pendingReceive: CheckedContinuation<WebSocketMessage, Error>?
    private var failure: Error?
    private var pings = 0

    public init() {}

    public func resume() async {
        resumed = true
    }

    public func send(_ message: WebSocketMessage) async throws {
        outbound.append(message)
    }

    public func receive() async throws -> WebSocketMessage {
        if let failure { throw failure }
        if !inbound.isEmpty { return inbound.removeFirst() }
        return try await withCheckedThrowingContinuation { continuation in
            pendingReceive = continuation
        }
    }

    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        closed = true
        storedCloseCode = closeCode
        storedCloseReason = reason.flatMap { String(data: $0, encoding: .utf8) }
        let error = WebSocketError.connectionClosed(code: closeCode, reason: storedCloseReason)
        failure = error
        resumePending(throwing: error)
    }

    public func sendPing() async throws {
        pings += 1
    }

    public var closeCode: URLSessionWebSocketTask.CloseCode {
        storedCloseCode
    }

    public var closeReason: String? {
        storedCloseReason
    }

    // MARK: - Test API

    /// Delivers an inbound frame to the next `receive()`.
    public func emit(_ message: WebSocketMessage) {
        guard let pendingReceive else {
            inbound.append(message)
            return
        }
        self.pendingReceive = nil
        pendingReceive.resume(returning: message)
    }

    /// Makes the next `receive()` throw, and every later one as well.
    public func fail(_ error: Error) {
        failure = error
        resumePending(throwing: error)
    }

    public func sentMessages() -> [WebSocketMessage] {
        outbound
    }

    public func wasClosed() -> Bool {
        closed
    }

    public func wasResumed() -> Bool {
        resumed
    }

    public func closeCodeUsed() -> URLSessionWebSocketTask.CloseCode {
        storedCloseCode
    }

    public func pingCount() -> Int {
        pings
    }

    private func resumePending(throwing error: Error) {
        guard let pendingReceive else { return }
        self.pendingReceive = nil
        pendingReceive.resume(throwing: error)
    }
}
