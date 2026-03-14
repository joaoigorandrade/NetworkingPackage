import Foundation

public enum NetworkError: Error, Sendable, Equatable {
    case invalidURL(String)
    case requestFailed(String)
    case httpError(statusCode: Int, data: Data?)
    case decodingError(String)
    case timeout
    case noInternetConnection
    case custom(String)
    case sslPinningFailure
    case cancelled
}
