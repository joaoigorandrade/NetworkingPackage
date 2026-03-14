import Foundation
import Networking

public struct TestAPIRequest<Response: Decodable & Sendable>: APIRequest {
    public let request: any HTTPRequest
    public let decoder: JSONDecoder

    public init(request: any HTTPRequest, decoder: JSONDecoder = JSONDecoder()) {
        self.request = request
        self.decoder = decoder
    }
}

public enum HTTPResponseFactory {
    public static func make(
        url: URL = URL(string: "https://example.com")!,
        statusCode: Int = 200,
        headers: [String: String] = [:],
        data: Data = Data()
    ) -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
        return (data, response)
    }
}
