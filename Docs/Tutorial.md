# Networking Tutorial

## Overview

This tutorial walks through the current baseline of the `Networking` package:

- Defining a typed API request
- Configuring a `URLSessionNetworkClient`
- Sending requests with async/await
- Handling `NetworkError`
- Testing requests with `NetworkingTestSupport`

The examples in this guide match the package as it exists today.

## Requirements

- Swift 6.2+
- iOS 13+ or macOS 10.15+
- Swift Package Manager

## Add the Package

If you are using SwiftPM directly, add the package dependency to your app package:

```swift
.package(path: "/path/to/Networking")
```

Then add `Networking` to your target dependencies:

```swift
.target(
    name: "App",
    dependencies: ["Networking"]
)
```

For tests, add `NetworkingTestSupport` to your test target:

```swift
.testTarget(
    name: "AppTests",
    dependencies: ["App", "NetworkingTestSupport"]
)
```

## Import the Module

```swift
import Networking
```

## Create a Response Model

Start with a model that matches the JSON returned by your API.

```swift
import Foundation

struct User: Decodable, Sendable {
    let id: Int
    let name: String
    let email: String
}
```

## Define an API Request

`APIRequest` connects a transport request with the typed response you want back.

```swift
import Foundation
import Networking

struct GetUserRequest: APIRequest {
    typealias Response = User

    let userID: Int

    var request: any HTTPRequest {
        HTTPRequestData(path: "/users/\(userID)")
            .method(.get)
            .header("Accept", "application/json")
    }
}
```

This package favors plain Swift request types. There are no macros or generated declarations to maintain.

## Configure a Client

Create one `URLSessionNetworkClient` with your API base URL.

```swift
import Foundation
import Networking

let client = URLSessionNetworkClient(
    baseURL: URL(string: "https://api.example.com")!
)
```

## Perform a Request

Call `request(for:)` to execute the request and decode the response automatically.

```swift
let user = try await client.request(for: GetUserRequest(userID: 42))
print(user.name)
```

Under the hood, the client will:

1. Build a `URLRequest` from your `HTTPRequest`
2. Execute it through `URLSession`
3. Validate that the status code is in `200..<300`
4. Decode the response body into `GetUserRequest.Response`

## Build Requests Fluently

`HTTPRequestData` supports a builder-style API for common request customization.

```swift
let request = HTTPRequestData(path: "/search")
    .method(.get)
    .header("Authorization", "Bearer token")
    .query([
        "query": "swift",
        "page": "1"
    ])
    .timeout(15)
```

You can also send JSON request bodies.

```swift
struct CreateUserBody: Encodable {
    let name: String
    let email: String
}

let createRequest = try HTTPRequestData(path: "/users")
    .method(.post)
    .header("Accept", "application/json")
    .jsonBody(CreateUserBody(name: "Taylor", email: "taylor@example.com"))
```

## POST Example

```swift
struct CreateUserResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let email: String
}

struct CreateUserRequest: APIRequest {
    typealias Response = CreateUserResponse

    let name: String
    let email: String

    var request: any HTTPRequest {
        let body = CreateUserBody(name: name, email: email)
        return try! HTTPRequestData(path: "/users")
            .method(.post)
            .header("Accept", "application/json")
            .jsonBody(body)
    }
}
```

A safer version avoids `try!` by preparing the request in an initializer.

```swift
struct SafeCreateUserRequest: APIRequest {
    typealias Response = CreateUserResponse

    let request: any HTTPRequest

    init(name: String, email: String) throws {
        let body = CreateUserBody(name: name, email: email)
        self.request = try HTTPRequestData(path: "/users")
            .method(.post)
            .header("Accept", "application/json")
            .jsonBody(body)
    }
}
```

## Handle Errors

The package surfaces failures through `NetworkError`.

```swift
import Networking

func loadUser(id: Int, client: URLSessionNetworkClient) async {
    do {
        let user = try await client.request(for: GetUserRequest(userID: id))
        print("Loaded user: \(user)")
    } catch let error as NetworkError {
        switch error {
        case .httpError(let statusCode, _):
            print("Server returned status code \(statusCode)")
        case .timeout:
            print("The request timed out")
        case .noInternetConnection:
            print("No internet connection is available")
        case .decodingError(let message):
            print("Failed to decode response: \(message)")
        case .cancelled:
            print("The request was cancelled")
        case .invalidURL(let url):
            print("Invalid URL: \(url)")
        case .requestFailed(let message):
            print("Request failed: \(message)")
        case .custom(let message):
            print("Custom error: \(message)")
        case .sslPinningFailure:
            print("SSL validation failed")
        }
    } catch {
        print("Unexpected error: \(error)")
    }
}
```

## Cancellation

The client cooperates with Swift concurrency cancellation.

```swift
let task = Task {
    try await client.request(for: GetUserRequest(userID: 42))
}

task.cancel()
```

If cancellation reaches the request before completion, the client throws `NetworkError.cancelled`.

## Custom Decoding

If an endpoint needs a specific decoder configuration, override `decoder`.

```swift
struct Event: Decodable, Sendable {
    let id: String
    let createdAt: Date
}

struct GetEventRequest: APIRequest {
    typealias Response = Event

    let eventID: String

    var request: any HTTPRequest {
        HTTPRequestData(path: "/events/\(eventID)")
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
```

## Testing with MockURLSession

`NetworkingTestSupport` includes a mock session so you can test request behavior without real network calls.

```swift
import Foundation
import Networking
import NetworkingTestSupport
import Testing

@Test
func loadsUser() async throws {
    let payload = try JSONEncoder().encode(User(id: 1, name: "Taylor", email: "taylor@example.com"))
    let session = MockURLSession { request in
        #expect(request.url?.absoluteString == "https://api.example.com/users/1")
        return HTTPResponseFactory.make(statusCode: 200, data: payload)
    }

    let client = URLSessionNetworkClient(
        baseURL: URL(string: "https://api.example.com")!,
        session: session
    )

    let user = try await client.request(for: GetUserRequest(userID: 1))

    #expect(user.name == "Taylor")
}
```

## Current Scope

The package currently includes:

- Core protocols for requests, responses, and clients
- A builder-style request type
- A `URLSession`-backed async client
- Automatic `Decodable` response decoding
- Test support utilities

## Recommended Project Structure

A simple app integration can look like this:

```text
App/
  API/
    Models/
    Requests/
    Client/
  Features/
  Tests/
```

A good starting split is:

- Put `Decodable` response types in `Models`
- Put `APIRequest` types in `Requests`
- Create and share one `URLSessionNetworkClient` in `Client`

## Next Steps

After this tutorial, the most natural follow-ups are:

1. Add request families for each endpoint in your API
2. Centralize authentication and common headers in shared request builders
3. Add tests for successful decoding, error mapping, and any custom decoders you introduce
4. Introduce cross-cutting features like interceptors only once you know what behavior should be shared
