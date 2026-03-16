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
        HTTPRequestData(path: "/users/\(userID)", apiVersion: .v1)
    }
}

struct AuthorizationInterceptor: RequestInterceptor {
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var interceptedRequest = request
        interceptedRequest.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        return interceptedRequest
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
func requestBuilderPrefixesVersionedRoutes() throws {
    let request = HTTPRequestData(path: "/groups", apiVersion: .v1, method: .post)

    let urlRequest = try request.makeURLRequest(
        configuration: NetworkConfiguration(
            baseURL: URL(string: "https://example.com")!,
            apiVersion: .v1
        )
    )

    #expect(urlRequest.url?.absoluteString == "https://example.com/v1/groups")
}

@Test
func requestBuilderKeepsRootRoutesOutsideVersionPrefix() throws {
    struct HealthCheckRequest: HTTPRequest {
        let path = "/health"
    }

    let urlRequest = try HealthCheckRequest().makeURLRequest(
        configuration: NetworkConfiguration(
            baseURL: URL(string: "https://example.com")!,
            apiVersion: .v1
        )
    )

    #expect(urlRequest.url?.absoluteString == "https://example.com/health")
}

@Test
func clientDecodesSuccessfulResponse() async throws {
    let payload = try JSONEncoder().encode(User(id: 1, name: "Taylor"))
    let session = MockURLSession { request in
        #expect(request.url?.absoluteString == "https://example.com/v1/users/1")
        return HTTPResponseFactory.make(statusCode: 200, data: payload)
    }
    let client = URLSessionNetworkClient(
        configuration: NetworkConfiguration(
            baseURL: URL(string: "https://example.com")!,
            apiVersion: .v1
        ),
        session: session
    )

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

@Test
func clientAppliesInterceptorsBeforeSendingRequest() async throws {
    let session = MockURLSession { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        return HTTPResponseFactory.make(statusCode: 200, data: Data("{}".utf8))
    }
    let client = URLSessionNetworkClient(
        configuration: NetworkConfiguration(baseURL: URL(string: "https://example.com")!, apiVersion: .v1),
        session: session,
        interceptors: [AuthorizationInterceptor()]
    )

    _ = try await client.execute(HTTPRequestData(path: "/groups", apiVersion: .v1))
}
