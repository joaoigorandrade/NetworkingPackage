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
}

public extension HTTPRequest {
    var apiVersion: APIVersion? { nil }
    var method: HTTPMethod { .get }
    var headers: [String: String] { [:] }
    var queryItems: [URLQueryItem] { [] }
    var body: Data? { nil }
    var timeoutInterval: TimeInterval? { nil }

    func makeURLRequest(baseURL: URL) throws -> URLRequest {
        let url = try resolvedURL(baseURL: baseURL)
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

    private func resolvedURL(baseURL: URL) throws -> URL {
        let normalizedPath = path.normalizedURLPath
        let versionedPath = normalizedPath.prefixed(with: apiVersion)
        let basePath = baseURL.path.normalizedURLPath
        let finalPath = [basePath, versionedPath]
            .filter { $0.isEmpty == false }
            .joined(separator: "/")
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }
        var updatedComponents = components
        updatedComponents.path = "/" + finalPath
        guard let url = updatedComponents.url else {
            throw NetworkError.invalidURL(baseURL.absoluteString + "/" + finalPath)
        }
        return url
    }
}

private extension String {
    var normalizedURLPath: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    func prefixed(with apiVersion: APIVersion?) -> String {
        guard let apiVersion else {
            return self
        }
        let versionPath = apiVersion.pathComponent
        guard hasPrefix(versionPath + "/") == false,
              self != versionPath else {
            return self
        }
        if isEmpty {
            return versionPath
        }
        return versionPath + "/" + self
    }
}
