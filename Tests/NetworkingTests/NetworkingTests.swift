import Foundation
import Testing
@testable import Networking
import NetworkingTestSupport

struct User: Codable, Equatable, Sendable {
    let id: Int
    let name: String
}

struct UserRequest: APIRequest {
    typealias Response = User

    let userID: Int

    var request: any HTTPRequest {
        HTTPRequestData(path: "/users/\(userID)")
    }
}

@Test
func requestBuilderCreatesExpectedURLRequest() throws {
    let request = HTTPRequestData(path: "/users")
        .method(.get)
        .header("Authorization", "Bearer token")
        .query(["page": "1", "filter": "active"])
        .timeout(30)

    let urlRequest = try request.makeURLRequest(baseURL: URL(string: "https://example.com/api")!)

    #expect(urlRequest.httpMethod == "GET")
    #expect(urlRequest.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    #expect(urlRequest.timeoutInterval == 30)
    #expect(urlRequest.url?.absoluteString == "https://example.com/api/users?page=1&filter=active" || urlRequest.url?.absoluteString == "https://example.com/api/users?filter=active&page=1")
}

@Test
func clientDecodesSuccessfulResponse() async throws {
    let payload = try JSONEncoder().encode(User(id: 1, name: "Taylor"))
    let session = MockURLSession { _ in
        HTTPResponseFactory.make(statusCode: 200, data: payload)
    }
    let client = URLSessionNetworkClient(baseURL: URL(string: "https://example.com")!, session: session)

    let user = try await client.request(for: UserRequest(userID: 1))

    #expect(user == User(id: 1, name: "Taylor"))
}

@Test
func clientMapsHTTPErrorStatus() async {
    let session = MockURLSession { _ in
        HTTPResponseFactory.make(statusCode: 404, data: Data("missing".utf8))
    }
    let client = URLSessionNetworkClient(baseURL: URL(string: "https://example.com")!, session: session)

    await #expect(throws: NetworkError.httpError(statusCode: 404, data: Data("missing".utf8))) {
        try await client.execute(HTTPRequestData(path: "/missing"))
    }
}

@Test
func clientMapsTimeoutError() async {
    let session = MockURLSession { _ in
        throw URLError(.timedOut)
    }
    let client = URLSessionNetworkClient(baseURL: URL(string: "https://example.com")!, session: session)

    await #expect(throws: NetworkError.timeout) {
        try await client.execute(HTTPRequestData(path: "/timeout"))
    }
}

@Test
func clientMapsCancellationError() async {
    let session = MockURLSession { _ in
        throw CancellationError()
    }
    let client = URLSessionNetworkClient(baseURL: URL(string: "https://example.com")!, session: session)

    await #expect(throws: NetworkError.cancelled) {
        try await client.execute(HTTPRequestData(path: "/cancelled"))
    }
}

@Test
func requestMapsDecodingFailure() async {
    let session = MockURLSession { _ in
        HTTPResponseFactory.make(statusCode: 200, data: Data("{}".utf8))
    }
    let client = URLSessionNetworkClient(baseURL: URL(string: "https://example.com")!, session: session)

    do {
        _ = try await client.request(for: UserRequest(userID: 1))
        Issue.record("Expected decoding failure")
    } catch let error as NetworkError {
        switch error {
        case .decodingError:
            break
        default:
            Issue.record("Expected decodingError, got \(error)")
        }
    } catch {
        Issue.record("Expected NetworkError, got \(error)")
    }
}
