# Architecture Notes

## Phase 1 Foundation

The package is split into three targets:

- `Networking`: public protocols, request builder, errors, and the `URLSession` client.
- `NetworkingMacros`: macro implementation target reserved for declarative API generation.
- `NetworkingTestSupport`: mock session and response builders used by tests and downstream adopters.

## Request Flow

1. An `APIRequest` exposes a transport-level `HTTPRequest` plus a decoder.
2. `URLSessionNetworkClient` converts that request into a `URLRequest` using the configured base URL.
3. The client executes through `URLSession`, validates the HTTP status code, and wraps the result in `NetworkResponse`.
4. The `APIRequest` decodes the typed response.

## Design Direction

This baseline keeps transport concerns separate from typed API decoding so later phases can add interceptors, telemetry, retries, and macros without rewriting the execution core.
