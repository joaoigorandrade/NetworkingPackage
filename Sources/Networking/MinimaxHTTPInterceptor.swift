import Foundation

public struct MinimaxHTTPInterceptor: HTTPInterceptor, Sendable {
    private let apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }

    public func intercept(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        return request
    }
}
