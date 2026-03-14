# Architecture Notes

## Modules

The package is split into two targets:

- `Networking`: public protocols, request builder, errors, and the `URLSession` client
- `NetworkingTestSupport`: mock session and response builders used by tests and downstream adopters

## Request Flow

1. An `APIRequest` exposes a transport-level `HTTPRequest` plus a decoder.
2. `URLSessionNetworkClient` converts that request into a `URLRequest` using the configured base URL.
3. The client executes through `URLSession`, validates the HTTP status code, and wraps the result in `NetworkResponse`.
4. The `APIRequest` decodes the typed response.

## Design Principles

- Keep transport concerns separate from typed decoding
- Prefer explicit Swift types over code generation
- Keep testability first-class through a mockable session boundary
- Add higher-level behavior without rewriting the execution core

## Extension Points

The current design leaves room for future additions such as:

- Interceptors or middleware around request execution
- Retry policies
- Observability hooks
- Specialized upload and download APIs
