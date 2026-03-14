import Foundation

public protocol APIRequest: Sendable {
    associatedtype Response: Decodable & Sendable
    var request: any HTTPRequest { get }
    var decoder: JSONDecoder { get }
    func decodeResponse(from response: NetworkResponse) throws -> Response
}

public extension APIRequest {
    var decoder: JSONDecoder { JSONDecoder() }

    func decodeResponse(from response: NetworkResponse) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: response.data)
        } catch {
            throw NetworkError.decodingError(String(describing: error))
        }
    }
}
