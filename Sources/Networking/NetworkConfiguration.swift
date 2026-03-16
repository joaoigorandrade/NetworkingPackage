import Foundation

public struct NetworkConfiguration: Sendable, Equatable {
    public let baseURL: URL
    public let apiVersion: APIVersion?

    public init(
        baseURL: URL,
        apiVersion: APIVersion? = nil
    ) {
        self.baseURL = baseURL
        self.apiVersion = apiVersion
    }

    public func url(
        for path: String,
        apiVersion: APIVersion? = nil
    ) throws -> URL {
        let normalizedPath = path.normalizedURLPath
        let resolvedPath = resolvedPath(
            normalizedPath,
            apiVersion: apiVersion
        )
        let basePath = baseURL.path.normalizedURLPath
        let finalPath = [basePath, resolvedPath]
            .filter { $0.isEmpty == false }
            .joined(separator: "/")
        guard let components = URLComponents(
            url: baseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidURL(baseURL.absoluteString)
        }
        var updatedComponents = components
        updatedComponents.path = "/" + finalPath
        guard let url = updatedComponents.url else {
            throw NetworkError.invalidURL(baseURL.absoluteString + "/" + finalPath)
        }
        return url
    }

    private func resolvedPath(
        _ normalizedPath: String,
        apiVersion: APIVersion?
    ) -> String {
        guard let apiVersion else {
            return normalizedPath
        }
        let versionPath = apiVersion.pathComponent
        guard normalizedPath.hasPrefix(versionPath + "/") == false,
              normalizedPath != versionPath else {
            return normalizedPath
        }
        if normalizedPath.isEmpty {
            return versionPath
        }
        return versionPath + "/" + normalizedPath
    }
}

private extension String {
    var normalizedURLPath: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
