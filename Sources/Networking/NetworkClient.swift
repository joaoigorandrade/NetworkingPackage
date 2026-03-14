import Foundation

public protocol NetworkClient: Sendable {
    var baseURL: URL { get }
    func execute(_ request: any HTTPRequest) async throws -> NetworkResponse
    func request<T: APIRequest>(for apiRequest: T) async throws -> T.Response
}

public extension NetworkClient {
    func request<T: APIRequest>(for apiRequest: T) async throws -> T.Response {
        let response = try await execute(apiRequest.request)
        return try apiRequest.decodeResponse(from: response)
    }
}
