import Foundation

public struct HTTPRequestData: HTTPRequest, Sendable, Equatable {
    public let path: String
    public let apiVersion: APIVersion?
    public let method: HTTPMethod
    public let headers: [String: String]
    public let queryItems: [URLQueryItem]
    public let body: Data?
    public let timeoutInterval: TimeInterval?

    public init(
        path: String,
        apiVersion: APIVersion? = nil,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        timeoutInterval: TimeInterval? = nil
    ) {
        self.path = path
        self.apiVersion = apiVersion
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.body = body
        self.timeoutInterval = timeoutInterval
    }

    public func method(_ method: HTTPMethod) -> Self {
        Self(
            path: path,
            apiVersion: apiVersion,
            method: method,
            headers: headers,
            queryItems: queryItems,
            body: body,
            timeoutInterval: timeoutInterval
        )
    }

    public func header(_ name: String, _ value: String) -> Self {
        var headers = headers
        headers[name] = value
        return Self(
            path: path,
            apiVersion: apiVersion,
            method: method,
            headers: headers,
            queryItems: queryItems,
            body: body,
            timeoutInterval: timeoutInterval
        )
    }

    public func query(_ values: [String: String?]) -> Self {
        let additionalItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return Self(
            path: path,
            apiVersion: apiVersion,
            method: method,
            headers: headers,
            queryItems: queryItems + additionalItems,
            body: body,
            timeoutInterval: timeoutInterval
        )
    }

    public func body(_ data: Data, contentType: String? = nil) -> Self {
        var updated = self.body(data)
        if let contentType {
            updated = updated.header("Content-Type", contentType)
        }
        return updated
    }

    public func jsonBody<T: Encodable>(_ value: T, encoder: JSONEncoder = JSONEncoder()) throws -> Self {
        let data = try encoder.encode(value)
        return body(data, contentType: "application/json")
    }

    public func body(_ data: Data) -> Self {
        Self(
            path: path,
            apiVersion: apiVersion,
            method: method,
            headers: headers,
            queryItems: queryItems,
            body: data,
            timeoutInterval: timeoutInterval
        )
    }

    public func timeout(_ interval: TimeInterval) -> Self {
        Self(
            path: path,
            apiVersion: apiVersion,
            method: method,
            headers: headers,
            queryItems: queryItems,
            body: body,
            timeoutInterval: interval
        )
    }
}
