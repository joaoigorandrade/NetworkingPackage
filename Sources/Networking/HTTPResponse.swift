import Foundation

public protocol HTTPResponse: Sendable {
    var statusCode: Int { get }
    var headers: [String: String] { get }
    var data: Data { get }
}
