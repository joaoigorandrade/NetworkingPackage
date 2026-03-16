import Foundation

public enum NetworkInterceptor: Sendable {
    case request(any HTTPInterceptor)
    case response(any HTTPInterceptor)
}
