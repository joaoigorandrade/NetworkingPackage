import Foundation

public protocol HTTPRequest: Sendable {
    var path: String { get }
    var method: HTTPMethod { get }
    var headers: [String: String] { get }
    var queryItems: [URLQueryItem] { get }
    var body: Data? { get }
    var timeoutInterval: TimeInterval? { get }
    func makeURLRequest(baseURL: URL) throws -> URLRequest
}

public extension HTTPRequest {
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem] { [] }
    var body: Data? { nil }
    var timeoutInterval: TimeInterval? { nil }

    func makeURLRequest(baseURL: URL) throws -> URLRequest {
        let normalizedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let url = baseURL.appendingPathComponent(normalizedPath)
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.appendingPathComponent(path).absoluteString)
        }
        if queryItems.isEmpty == false {
            components.queryItems = queryItems
        }
        guard let finalURL = components.url else {
            throw NetworkError.invalidURL(baseURL.appendingPathComponent(path).absoluteString)
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
