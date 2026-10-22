import Foundation

/// The transport seam a `WebSocketClient` drives, so tests can substitute a fake socket.
public protocol WebSocketTaskHandle: Sendable {
    func resume() async
    func send(_ message: WebSocketMessage) async throws
    func receive() async throws -> WebSocketMessage
    func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async
    func sendPing() async throws
    var closeCode: URLSessionWebSocketTask.CloseCode { get async }
    var closeReason: String? { get async }
}

public extension WebSocketTaskHandle {
    var closeCode: URLSessionWebSocketTask.CloseCode { get async { .invalid } }
    var closeReason: String? { get async { nil } }
}

/// Creates transport handles for handshake requests.
public protocol WebSocketTaskFactory: Sendable {
    func makeTask(_ request: URLRequest) -> any WebSocketTaskHandle
}

/// A `WebSocketTaskHandle` backed by `URLSessionWebSocketTask`.
public struct URLSessionWebSocketTaskHandle: WebSocketTaskHandle {
    private let task: URLSessionWebSocketTask

    public init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    public func resume() async {
        task.resume()
    }

    public func send(_ message: WebSocketMessage) async throws {
        switch message {
        case let .string(text): try await task.send(.string(text))
        case let .data(data): try await task.send(.data(data))
        }
    }

    public func receive() async throws -> WebSocketMessage {
        switch try await task.receive() {
        case let .string(text): return .string(text)
        case let .data(data): return .data(data)
        @unknown default: throw WebSocketError.invalidMessage
        }
    }

    public func cancel(with closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) async {
        task.cancel(with: closeCode, reason: reason)
    }

    public func sendPing() async throws {
        // The SDK only exposes the ObjC pong handler, so it is bridged into async/await here.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    public var closeCode: URLSessionWebSocketTask.CloseCode {
        task.closeCode
    }

    public var closeReason: String? {
        task.closeReason.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Creates `URLSessionWebSocketTask` handles.
public struct URLSessionWebSocketTaskFactory: WebSocketTaskFactory {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func makeTask(_ request: URLRequest) -> any WebSocketTaskHandle {
        URLSessionWebSocketTaskHandle(task: session.webSocketTask(with: request))
    }
}
