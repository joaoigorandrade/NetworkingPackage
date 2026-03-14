# Networking

Modern Swift networking library targeting Swift 6.2+ with async/await, Swift macros, test support, and an incremental roadmap for observability, interceptors, and security.

## Current Baseline

- SwiftPM package with `Networking`, `NetworkingMacros`, and `NetworkingTestSupport`
- Core protocols for requests, responses, API requests, and clients
- `URLSession`-backed async client with error mapping and status validation
- Builder-style `HTTPRequestData`
- Codable response decoding
- Test support for mocking `URLSession`

## Next Milestones

- Real macro expansion for `@Request`, `@Client`, and `@Parameter`
- Interceptor pipeline
- OpenTelemetry integration
- Upload, download, caching, and SSL pinning
