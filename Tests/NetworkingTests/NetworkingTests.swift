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

struct AuthorizationInterceptor: HTTPInterceptor {
    func intercept(_ request: URLRequest) async throws -> URLRequest {
        var interceptedRequest = request
        interceptedRequest.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        return interceptedRequest
    }
}

actor TestNetworkLogger: NetworkLogging {
    private(set) var entries: [NetworkLog] = []

    func log(_ entry: NetworkLog) async {
        entries.append(entry)
    }

    func snapshot() -> [NetworkLog] {
        entries
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

    let urlRequest = try request.makeURLRequest(baseURL: URL(string: "https://example.com")!)

    #expect(urlRequest.url?.absoluteString == "https://example.com/v1/groups")
}

@Test
func requestBuilderKeepsRootRoutesOutsideVersionPrefix() throws {
    struct HealthCheckRequest: HTTPRequest {
        let path = "/health"
    }

    let urlRequest = try HealthCheckRequest().makeURLRequest(baseURL: URL(string: "https://example.com")!)

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
        baseURL: URL(string: "https://example.com")!,
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
        baseURL: URL(string: "https://example.com")!,
        session: session,
        interceptors: [.request(AuthorizationInterceptor())]
    )

    _ = try await client.execute(HTTPRequestData(path: "/groups", apiVersion: .v1))
}

@Test
func clientLogsRequestAndResponse() async throws {
    let logger = TestNetworkLogger()
    let payload = Data("{\"id\":1}".utf8)
    let session = MockURLSession { request in
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        return HTTPResponseFactory.make(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            data: payload
        )
    }
    let client = URLSessionNetworkClient(
        baseURL: URL(string: "https://example.com")!,
        session: session,
        logger: logger
    )

    _ = try await client.execute(
        HTTPRequestData(path: "/groups")
            .method(.post)
            .header("Content-Type", "application/json")
            .body(Data("{\"name\":\"Weekend\"}".utf8))
    )

    let entries = await logger.snapshot()

    #expect(entries.count == 2)
    #expect(entries[0].kind == .request)
    #expect(entries[0].method == "POST")
    #expect(entries[0].url == "https://example.com/groups")
    #expect(entries[0].requestBody == "{\"name\":\"Weekend\"}")
    #expect(entries[1].kind == .response)
    #expect(entries[1].responseStatusCode == 200)
    #expect(entries[1].responseHeaders["Content-Type"] == "application/json")
    #expect(entries[1].responseBody == "{\"id\":1}")
    #expect(entries[1].duration != nil)
}

@Test
func clientLogsFailures() async {
    let logger = TestNetworkLogger()
    let session = MockURLSession { _ in
        throw URLError(.timedOut)
    }
    let client = URLSessionNetworkClient(
        baseURL: URL(string: "https://example.com")!,
        session: session,
        logger: logger
    )

    await #expect(throws: NetworkError.timeout) {
        try await client.execute(HTTPRequestData(path: "/timeout"))
    }

    let entries = await logger.snapshot()

    #expect(entries.count == 2)
    #expect(entries[0].kind == .request)
    #expect(entries[1].kind == .failure)
    #expect(entries[1].errorDescription == String(describing: NetworkError.timeout))
    #expect(entries[1].duration != nil)
}
