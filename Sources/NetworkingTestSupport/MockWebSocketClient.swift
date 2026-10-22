import Foundation
import Networking
import Synchronization

/// A factory that records handshake requests and hands out fake socket transports.
public final class MockWebSocketTaskFactory: WebSocketTaskFactory, Sendable {
    private struct State {
        var requests: [URLRequest] = []
        var tasks: [MockWebSocketTask] = []
    }

    private let state = Mutex(State())
    private let template: MockWebSocketTask?

    public init(task: MockWebSocketTask? = nil) {
        self.template = task
    }

    public func makeTask(_ request: URLRequest) -> any WebSocketTaskHandle {
        state.withLock { s in
            s.requests.append(request)
            if let template { return template }
            let task = MockWebSocketTask()
            s.tasks.append(task)
            return task
        }
    }

    public func requests() -> [URLRequest] {
        state.withLock { $0.requests }
    }

    public func lastRequest() -> URLRequest? {
        state.withLock { $0.requests.last }
    }

    public func createdTasks() -> [MockWebSocketTask] {
        state.withLock { $0.tasks }
    }

    public func taskCount() -> Int {
        state.withLock { $0.tasks.count }
    }
}

/// An in-memory `WebSocketClient` for testing consumer code without a socket.
public final class MockWebSocketClient: WebSocketClient, Sendable {
    private struct State {
        var isConnected = false
        var sent: [WebSocketMessage] = []
    }

    private let state = Mutex(State())
    private let stream: AsyncThrowingStream<WebSocketMessage, Error>
    private let continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation

    public init() {
        let (stream, continuation) = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    public var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    public func messages() -> AsyncThrowingStream<WebSocketMessage, Error> {
        stream
    }

    public func connect() async throws {
        state.withLock { $0.isConnected = true }
    }

    public func send(_ message: WebSocketMessage) async throws {
        let isConnected = state.withLock { $0.isConnected }
        guard isConnected else { throw WebSocketError.notConnected }
        state.withLock { $0.sent.append(message) }
    }

    public func close() async {
        state.withLock { $0.isConnected = false }
        continuation.finish()
    }

    public func emit(_ message: WebSocketMessage) {
        continuation.yield(message)
    }

    public func fail(_ error: Error) {
        continuation.finish(throwing: error)
    }

    public func sentMessages() -> [WebSocketMessage] {
        state.withLock { $0.sent }
    }
}
