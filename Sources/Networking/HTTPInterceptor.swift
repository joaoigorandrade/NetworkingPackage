import Foundation

public protocol HTTPInterceptor: Sendable {
    func intercept(_ request: URLRequest) async throws -> URLRequest
    func intercept(response: HTTPURLResponse, data: Data, request: URLRequest) async
}

public extension HTTPInterceptor {
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        request
    }

    func intercept(response: HTTPURLResponse, data: Data, request: URLRequest) async {}
}
