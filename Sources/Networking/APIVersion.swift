import Foundation

public enum APIVersion: String, Sendable, Equatable {
    case v1 = "V1"
    case v2 = "V2"

    var pathComponent: String {
        rawValue.lowercased()
    }
}
