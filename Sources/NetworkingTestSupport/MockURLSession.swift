import Foundation
import Networking

public final actor MockURLSession: URLSessionProtocol {
    public typealias Handler = @Sendable (URLRequest) throws -> (Data, URLResponse)

    private let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try handler(request)
    }
}
