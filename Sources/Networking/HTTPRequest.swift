import Foundation

public protocol HTTPRequest: Sendable {
    var path: String { get }
    var apiVersion: APIVersion? { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem] { get }
    var body: Data? { get }
    var timeoutInterval: TimeInterval? { get }
    func makeURLRequest(baseURL: URL) throws -> URLRequest
    func makeURLRequest(configuration: NetworkConfiguration) throws -> URLRequest
}

public extension HTTPRequest {
    var apiVersion: APIVersion? { nil }
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem] { [] }
    var body: Data? { nil }
    var timeoutInterval: TimeInterval? { nil }

    func makeURLRequest(baseURL: URL) throws -> URLRequest {
        try makeURLRequest(configuration: NetworkConfiguration(baseURL: baseURL))
    }

    func makeURLRequest(configuration: NetworkConfiguration) throws -> URLRequest {
        let url = try configuration.url(
            for: path,
            apiVersion: apiVersion
        )
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(url.absoluteString)
        }
        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL(url.absoluteString)
        }
        var request = URLRequest(url: finalURL)
        request.httpMethod = method.rawValue
        request.httpBody = body
        if let timeoutInterval {
            request.timeoutInterval = timeoutInterval
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }
}
