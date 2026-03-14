import Foundation

public struct NetworkResponse: HTTPResponse, Sendable, Equatable {
    public let statusCode: Int
    public let headers: [String: String]
    public let data: Data

    public init(statusCode: Int, headers: [String: String], data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.data = data
    }
}
