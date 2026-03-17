import Foundation

public struct NetworkLog: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case request
        case response
        case failure
    }

    public let kind: Kind
    public let method: String
    public let url: String
    public let requestHeaders: [String: String]
    public let requestBody: String?
    public let responseStatusCode: Int?
    public let responseHeaders: [String: String]
    public let responseBody: String?
    public let errorDescription: String?
    public let duration: TimeInterval?
    public let timestamp: Date

    public init(
        kind: Kind,
        method: String,
        url: String,
        requestHeaders: [String: String],
        requestBody: String?,
        responseStatusCode: Int? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        errorDescription: String? = nil,
        duration: TimeInterval? = nil,
        timestamp: Date = Date()
    ) {
        self.kind = kind
        self.method = method
        self.url = url
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatusCode = responseStatusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.errorDescription = errorDescription
        self.duration = duration
        self.timestamp = timestamp
    }

    public static func request(from request: URLRequest, timestamp: Date = Date()) -> Self {
        Self(
            kind: .request,
            method: request.httpMethod ?? HTTPMethod.get.rawValue,
            url: request.url?.absoluteString ?? "unknown",
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: request.httpBody?.logRepresentation,
            timestamp: timestamp
        )
    }

    public static func response(
        for request: URLRequest,
        response: HTTPURLResponse,
        data: Data,
        duration: TimeInterval?,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            kind: .response,
            method: request.httpMethod ?? HTTPMethod.get.rawValue,
            url: request.url?.absoluteString ?? "unknown",
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: request.httpBody?.logRepresentation,
            responseStatusCode: response.statusCode,
            responseHeaders: response.logHeaders,
            responseBody: data.logRepresentation,
            duration: duration,
            timestamp: timestamp
        )
    }

    public static func failure(
        for request: URLRequest,
        error: Error,
        duration: TimeInterval?,
        timestamp: Date = Date()
    ) -> Self {
        Self(
            kind: .failure,
            method: request.httpMethod ?? HTTPMethod.get.rawValue,
            url: request.url?.absoluteString ?? "unknown",
            requestHeaders: request.allHTTPHeaderFields ?? [:],
            requestBody: request.httpBody?.logRepresentation,
            errorDescription: String(describing: error),
            duration: duration,
            timestamp: timestamp
        )
    }

    public var formattedMessage: String {
        var lines = ["[Networking][\(kind.rawValue.uppercased())] \(method) \(url)"]

        if requestHeaders.isEmpty == false {
            lines.append("Request Headers: \(requestHeaders.sortedDescription)")
        }

        if let requestBody {
            lines.append("Request Body: \(requestBody)")
        }

        if let responseStatusCode {
            lines.append("Status: \(responseStatusCode)")
        }

        if responseHeaders.isEmpty == false {
            lines.append("Response Headers: \(responseHeaders.sortedDescription)")
        }

        if let responseBody {
            lines.append("Response Body: \(responseBody)")
        }

        if let errorDescription {
            lines.append("Error: \(errorDescription)")
        }

        if let duration {
            lines.append("Duration: \(Int((duration * 1000).rounded()))ms")
        }

        return lines.joined(separator: "\n")
    }
}

public protocol NetworkLogging: Sendable {
    func log(_ entry: NetworkLog) async
}

public actor ConsoleNetworkLogger: NetworkLogging {
    public init() {}

    public func log(_ entry: NetworkLog) async {
        print(entry.formattedMessage)
    }
}

private extension Data {
    var logRepresentation: String? {
        guard isEmpty == false else {
            return nil
        }

        if let string = String(data: self, encoding: .utf8) {
            return string
        }

        return base64EncodedString()
    }
}

private extension HTTPURLResponse {
    var logHeaders: [String: String] {
        allHeaderFields.reduce(into: [:]) { partialResult, pair in
            guard let key = pair.key as? String else {
                return
            }

            partialResult[key] = String(describing: pair.value)
        }
    }
}

private extension Dictionary where Key == String, Value == String {
    var sortedDescription: String {
        sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }
}
