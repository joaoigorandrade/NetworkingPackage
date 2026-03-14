# Networking

Modern Swift networking library targeting Swift 6.2+ with async/await, typed requests, and test support.

## What Is Included

- `Networking` for request protocols, request building, response decoding, and the `URLSession` client
- `NetworkingTestSupport` for mocking `URLSession` in tests
- `HTTPRequestData` for fluent request construction
- `APIRequest` for typed `Decodable` responses
- `URLSessionNetworkClient` for async request execution and error mapping

## Package Structure

- [Tutorial](Docs/Tutorial.md)
- [Architecture Notes](Docs/Architecture.md)

## Current Focus

The package is now intentionally small and explicit. Requests are written as regular Swift types instead of generated through macros, which keeps the public API straightforward and removes the `swift-syntax` toolchain dependency.

## Likely Next Steps

- Add more request types that model your real endpoints
- Introduce shared helpers for authentication headers or common query parameters
- Expand tests around request building and failure handling
- Add higher-level features like interceptors, retries, or observability only when a concrete need appears
