import Foundation

public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

public struct URLSessionNetworkClient: NetworkClient, Sendable {
    public let baseURL: URL
    public let session: any URLSessionProtocol
    public let successStatusCodes: Range<Int>

    public init(
        baseURL: URL,
        session: any URLSessionProtocol = URLSession.shared,
        successStatusCodes: Range<Int> = 200..<300
    ) {
        self.baseURL = baseURL
        self.session = session
        self.successStatusCodes = successStatusCodes
    }

    public func execute(_ request: any HTTPRequest) async throws -> NetworkResponse {
        try Task.checkCancellation()
        let urlRequest = try request.makeURLRequest(baseURL: baseURL)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            try Task.checkCancellation()
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.requestFailed("Response was not an HTTPURLResponse")
            }
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
}
