import Foundation

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public struct URLSessionNetworkClient: NetworkClient, Sendable {
    public let baseURL: URL
    public let session: any URLSessionProtocol
    public let successStatusCodes: Range<Int>
    public let interceptors: [NetworkInterceptor]
    public let logger: (any NetworkLogging)?

    public init(
        baseURL: URL,
        session: any URLSessionProtocol = URLSession.shared,
        successStatusCodes: Range<Int> = 200..<300,
        interceptors: [NetworkInterceptor] = [],
        logger: (any NetworkLogging)? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.successStatusCodes = successStatusCodes
        self.interceptors = interceptors
        self.logger = logger
    }

    public func execute(_ request: any HTTPRequest) async throws -> NetworkResponse {
        try Task.checkCancellation()
        let urlRequest = try await applyInterceptors(
            to: request.makeURLRequest(baseURL: baseURL)
        )
        let startedAt = Date()
        await log(.request(from: urlRequest, timestamp: startedAt))
        do {
            let (data, response) = try await session.data(for: urlRequest)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.requestFailed("Response was not an HTTPURLResponse")
            }
            await applyResponseInterceptors(
                response: httpResponse,
                data: data,
                request: urlRequest
            )
            await log(
                .response(
                    for: urlRequest,
                    response: httpResponse,
                    data: data,
                    duration: Date().timeIntervalSince(startedAt)
                )
            )
            guard successStatusCodes.contains(httpResponse.statusCode) else {
                throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
            return NetworkResponse(
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields.reduce(into: [:]) { partialResult, pair in
                    guard let key = pair.key as? String else { return }
                    partialResult[key] = String(describing: pair.value)
                },
                data: data
            )
        } catch is CancellationError {
            await log(
                .failure(
                    for: urlRequest,
                    error: NetworkError.cancelled,
                    duration: Date().timeIntervalSince(startedAt)
                )
            )
            throw NetworkError.cancelled
        } catch let error as URLError {
            let mappedError = map(error)
            await log(
                .failure(
                    for: urlRequest,
                    error: mappedError,
                    duration: Date().timeIntervalSince(startedAt)
                )
            )
            throw mappedError
        } catch let error as NetworkError {
            await log(
                .failure(
                    for: urlRequest,
                    error: error,
                    duration: Date().timeIntervalSince(startedAt)
                )
            )
            throw error
        } catch {
            let wrappedError = NetworkError.requestFailed(String(describing: error))
            await log(
                .failure(
                    for: urlRequest,
                    error: wrappedError,
                    duration: Date().timeIntervalSince(startedAt)
                )
            )
            throw wrappedError
        }
    }

    private func log(_ entry: NetworkLog) async {
        await logger?.log(entry)
    }

    private func map(_ error: URLError) -> NetworkError {
        switch error.code {
        case .timedOut:
            return .timeout
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .noInternetConnection
        case .cancelled:
            return .cancelled
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted, .serverCertificateHasUnknownRoot, .clientCertificateRejected, .clientCertificateRequired:
            return .sslPinningFailure
        default:
            return .requestFailed(error.localizedDescription)
        }
    }

    private func applyInterceptors(to request: URLRequest) async throws -> URLRequest {
        var interceptedRequest = request
        for interceptor in interceptors {
            guard case let .request(requestInterceptor) = interceptor else {
                continue
            }
            interceptedRequest = try await requestInterceptor.intercept(interceptedRequest)
        }
        return interceptedRequest
    }

    private func applyResponseInterceptors(
        response: HTTPURLResponse,
        data: Data,
        request: URLRequest
    ) async {
        for interceptor in interceptors {
            guard case let .response(responseInterceptor) = interceptor else {
                continue
            }
            await responseInterceptor.intercept(response: response, data: data, request: request)
        }
    }
}
