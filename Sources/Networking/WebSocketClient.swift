import Foundation

/// A frame received from, or sent to, a WebSocket endpoint.
public enum WebSocketMessage: Sendable, Equatable {
    case string(String)
    case data(Data)

    /// The textual payload, or `nil` when the frame carries binary data.
    public var text: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    /// The raw bytes of the frame, encoding text frames as UTF-8.
    public var payload: Data {
        switch self {
        case let .string(value): Data(value.utf8)
        case let .data(value): value
        }
    }
}

/// Connection settings for a WebSocket session.
public struct WebSocketConfiguration: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public let subprotocols: [String]
    public let timeoutInterval: TimeInterval
    public let pingInterval: TimeInterval?
    public let maxReconnectAttempts: Int
    public let reconnectBackoff: TimeInterval

    /// - Parameters:
    ///   - url: The `ws`/`wss` endpoint to connect to.
    ///   - headers: Extra HTTP headers sent with the handshake request.
    ///   - subprotocols: Subprotocols advertised through the `Sec-WebSocket-Protocol` header.
    ///   - timeoutInterval: Handshake timeout, in seconds.
    ///   - pingInterval: Keepalive ping interval, in seconds. `nil` disables keepalive pings.
    ///   - maxReconnectAttempts: How many times a dropped connection is retried. `0` disables reconnection.
    ///   - reconnectBackoff: Base delay, in seconds, doubled on every attempt and capped at 30 seconds.
    public init(
        url: URL,
        headers: [String: String] = [:],
        subprotocols: [String] = [],
        timeoutInterval: TimeInterval = 30,
        pingInterval: TimeInterval? = nil,
        maxReconnectAttempts: Int = 5,
        reconnectBackoff: TimeInterval = 0.5
    ) {
        self.url = url
        self.headers = headers
        self.subprotocols = subprotocols
        self.timeoutInterval = timeoutInterval
        self.pingInterval = pingInterval
        self.maxReconnectAttempts = maxReconnectAttempts
        self.reconnectBackoff = reconnectBackoff
    }
}

/// A WebSocket transport that streams messages from a server.
public protocol WebSocketClient: Sendable {
    /// Opens the connection. Throws `WebSocketError.notConnected` when the client was already closed.
    func connect() async throws

    /// Sends a frame to the server. Throws `WebSocketError.notConnected` while disconnected.
    func send(_ message: WebSocketMessage) async throws

    /// The inbound message stream. It stays open until `close()` is called or the client fails terminally.
    func messages() -> AsyncThrowingStream<WebSocketMessage, Error>

    /// Closes the connection and finishes the message stream without an error.
    func close() async

    /// Whether a transport is currently attached.
    var isConnected: Bool { get }
}
