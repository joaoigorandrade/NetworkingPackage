import Foundation

public enum WebSocketError: Error, Sendable, Equatable {
    case notConnected
    case handshakeFailed(statusCode: Int?)
    case connectionClosed(code: URLSessionWebSocketTask.CloseCode, reason: String?)
    case reconnectLimitExceeded(attempts: Int)
    case invalidMessage
    case transportFailure(String)
}
