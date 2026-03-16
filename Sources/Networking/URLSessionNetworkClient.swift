import Foundation

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public struct URLSessionNetworkClient: NetworkClient, Sendable {
    public let configuration: NetworkConfiguration
    public let session: any URLSessionProtocol
    public let successStatusCodes: Range<Int>
    public let interceptors: [NetworkInterceptor]

    public var baseURL: URL {
        configuration.baseURL
    }

    public init(
        baseURL: URL,
        session: any URLSessionProtocol = URLSession.shared,
        successStatusCodes: Range<Int> = 200..<300,
        interceptors: [NetworkInterceptor] = []
    ) {
        self.configuration = NetworkConfiguration(baseURL: baseURL)
        self.session = session
        self.successStatusCodes = successStatusCodes
        self.interceptors = interceptors
    }

    public init(
        configuration: NetworkConfiguration,
        session: any URLSessionProtocol = URLSession.shared,
        successStatusCodes: Range<Int> = 200..<300,
        interceptors: [NetworkInterceptor] = []
    ) {
        self.configuration = configuration
        self.session = session
        self.successStatusCodes = successStatusCodes
        self.interceptors = interceptors
    }

    public func execute(_ request: any HTTPRequest) async throws -> NetworkResponse {
        try Task.checkCancellation()
        let urlRequest = try await applyInterceptors(
            to: request.makeURLRequest(configuration: configuration)
        )
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
            throw NetworkError.cancelled
        } catch let error as URLError {
            throw map(error)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.requestFailed(String(describing: error))
        }
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
