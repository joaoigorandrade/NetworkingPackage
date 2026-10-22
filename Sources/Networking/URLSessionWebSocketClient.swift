import Foundation
import Synchronization

/// A `WebSocketClient` backed by `URLSessionWebSocketTask`.
///
/// The client owns a single session lifecycle: `connect()` opens the socket, `messages()`
/// streams inbound frames until the socket closes, and `close()` shuts everything down.
/// Transient disconnects are retried with exponential backoff and never terminate the stream.
public final class URLSessionWebSocketClient: WebSocketClient, Sendable {
    private struct State: Sendable {
        var handle: (any WebSocketTaskHandle)?
        var isConnected = false
        var isTerminated = false
        var reconnectAttempts = 0
        var generation = 0
        var receiveLoop: Task<Void, Never>?
        var pingTask: Task<Void, Never>?
    }

    private enum FailureDecision: Sendable {
        case stale
        case finished
        case reconnect(delay: TimeInterval)
        case failed(WebSocketError)
    }

    private let configuration: WebSocketConfiguration
    private let factory: any WebSocketTaskFactory
    private let state = Mutex(State())
    private let stream: AsyncThrowingStream<WebSocketMessage, Error>
    private let continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation

    public init(
        configuration: WebSocketConfiguration,
        factory: any WebSocketTaskFactory = URLSessionWebSocketTaskFactory()
    ) {
        self.configuration = configuration
        self.factory = factory
        let (stream, continuation) = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
        self.stream = stream
        self.continuation = continuation
        continuation.onTermination = { @Sendable termination in
            guard case .cancelled = termination else { return }
            Task { [weak self] in
                await self?.cancelTransport()
            }
        }
    }

    // MARK: - Public API

    public var isConnected: Bool {
        state.withLock { $0.isConnected }
    }

    public func messages() -> AsyncThrowingStream<WebSocketMessage, Error> {
        stream
    }

    public func connect() async throws {
        try Task.checkCancellation()
        await detachTransport(closeCode: .goingAway)
        guard !state.withLock({ $0.isTerminated }) else {
            throw WebSocketError.notConnected
        }

        let handle = factory.makeTask(makeRequest())
        await handle.resume()

        let generation = state.withLock { s -> Int in
            s.handle = handle
            s.isConnected = true
            s.reconnectAttempts = 0
            s.generation += 1
            return s.generation
        }

        startPing(generation: generation)
        startReceiveLoop(generation: generation)
    }

    public func send(_ message: WebSocketMessage) async throws {
        let handle = state.withLock { s -> (any WebSocketTaskHandle)? in
            guard s.isConnected else { return nil }
            return s.handle
        }
        guard let handle else {
            throw WebSocketError.notConnected
        }

        do {
            try await handle.send(message)
        } catch {
            let closeCode = await handle.closeCode
            let closeReason = await handle.closeReason
            throw mapFailure(error, closeCode: closeCode, closeReason: closeReason)
        }
    }

    public func close() async {
        state.withLock { $0.isTerminated = true }
        await detachTransport(closeCode: .normalClosure)
        continuation.finish()
    }

    // MARK: - Transport Lifecycle

    private func detachTransport(closeCode: URLSessionWebSocketTask.CloseCode) async {
        let handle = state.withLock { s -> (any WebSocketTaskHandle)? in
            s.isConnected = false
            s.receiveLoop?.cancel()
            s.receiveLoop = nil
            s.pingTask?.cancel()
            s.pingTask = nil
            let handle = s.handle
            s.handle = nil
            return handle
        }
        await handle?.cancel(with: closeCode, reason: nil)
    }

    private func cancelTransport() async {
        state.withLock { $0.isTerminated = true }
        await detachTransport(closeCode: .goingAway)
    }

    private func finishStream() async {
        state.withLock { $0.isTerminated = true }
        await detachTransport(closeCode: .goingAway)
        continuation.finish()
    }

    private func finishStream(throwing error: Error) async {
        state.withLock { $0.isTerminated = true }
        await detachTransport(closeCode: .goingAway)
        continuation.finish(throwing: error)
    }

    // MARK: - Receive Loop

    private func startReceiveLoop(generation: Int) {
        let task = Task { [weak self] in
            if let self {
                await self.receiveLoop(generation: generation)
            }
        }
        state.withLock { s in
            s.receiveLoop?.cancel()
            s.receiveLoop = task
        }
    }

    private func receiveLoop(generation: Int) async {
        while !Task.isCancelled {
            guard let handle = state.withLock({ s in
                s.generation == generation ? s.handle : nil
            }) else {
                return
            }

            do {
                let message = try await withTaskCancellationHandler {
                    try await handle.receive()
                } onCancel: {
                    Task { await handle.cancel(with: .goingAway, reason: nil) }
                }
                guard state.withLock({ $0.generation == generation }) else { return }
                continuation.yield(message)
            } catch {
                await handleFailure(error, generation: generation, handle: handle)
                return
            }
        }
    }

    private func handleFailure(
        _ error: Error,
        generation: Int,
        handle: any WebSocketTaskHandle
    ) async {
        let closeCode = await handle.closeCode
        let closeReason = await handle.closeReason

        let decision = state.withLock { s -> FailureDecision in
            guard s.generation == generation else { return .stale }
            guard !s.isTerminated else { return .finished }
            if error is CancellationError || Task.isCancelled { return .finished }

            if configuration.maxReconnectAttempts > 0,
               s.reconnectAttempts < configuration.maxReconnectAttempts {
                s.reconnectAttempts += 1
                let attempt = s.reconnectAttempts
                s.handle = nil
                s.isConnected = false
                s.generation += 1
                return .reconnect(delay: backoff(for: attempt))
            }

            s.isTerminated = true
            s.isConnected = false
            if configuration.maxReconnectAttempts == 0 {
                return .failed(mapFailure(error, closeCode: closeCode, closeReason: closeReason))
            }
            return .failed(.reconnectLimitExceeded(attempts: s.reconnectAttempts))
        }

        switch decision {
        case .stale:
            return
        case .finished:
            await finishStream()
        case let .reconnect(delay):
            await reconnect(after: delay)
        case let .failed(error):
            await finishStream(throwing: error)
        }
    }

    private func reconnect(after delay: TimeInterval) async {
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            await finishStream()
            return
        }

        guard !state.withLock({ $0.isTerminated }) else { return }

        let handle = factory.makeTask(makeRequest())
        await handle.resume()

        let generation = state.withLock { s -> Int? in
            guard !s.isTerminated else { return nil }
            s.handle = handle
            s.isConnected = true
            s.generation += 1
            return s.generation
        }

        guard let generation else {
            await handle.cancel(with: .normalClosure, reason: nil)
            return
        }

        startPing(generation: generation)
        startReceiveLoop(generation: generation)
    }

    // MARK: - Keepalive

    private func startPing(generation: Int) {
        guard let interval = configuration.pingInterval, interval > 0 else { return }

        let task = Task { [weak self] in
            if let self {
                await self.pingLoop(generation: generation, interval: interval)
            }
        }
        state.withLock { s in
            s.pingTask?.cancel()
            s.pingTask = task
        }
    }

    private func pingLoop(generation: Int, interval: TimeInterval) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(interval))
            } catch {
                return
            }

            guard let handle = state.withLock({ s in
                s.generation == generation ? s.handle : nil
            }) else {
                return
            }

            do {
                try await handle.sendPing()
            } catch {
                await handleFailure(error, generation: generation, handle: handle)
                return
            }
        }
    }

    // MARK: - Helpers

    private func makeRequest() -> URLRequest {
        var request = URLRequest(
            url: configuration.url,
            timeoutInterval: configuration.timeoutInterval
        )
        for (field, value) in configuration.headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        if !configuration.subprotocols.isEmpty {
            request.setValue(
                configuration.subprotocols.joined(separator: ", "),
                forHTTPHeaderField: "Sec-WebSocket-Protocol"
            )
        }
        return request
    }

    private func backoff(for attempt: Int) -> TimeInterval {
        let scaled = configuration.reconnectBackoff * pow(2, Double(max(0, attempt - 1)))
        return min(scaled, 30)
    }

    private func mapFailure(
        _ error: Error,
        closeCode: URLSessionWebSocketTask.CloseCode,
        closeReason: String?
    ) -> WebSocketError {
        if let webSocketError = error as? WebSocketError {
            return webSocketError
        }
        if closeCode != .invalid {
            return .connectionClosed(code: closeCode, reason: closeReason)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .badServerResponse:
                return .handshakeFailed(statusCode: nil)
            default:
                return .transportFailure(urlError.localizedDescription)
            }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorBadServerResponse {
            return .handshakeFailed(statusCode: nil)
        }
        return .transportFailure(String(describing: error))
    }
}
