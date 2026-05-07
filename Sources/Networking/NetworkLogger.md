# Network Logger

`NetworkLog` models request, response, and failure events emitted by `URLSessionNetworkClient`.

## What It Captures

- HTTP method and URL
- Request headers and body
- Response status code, headers, and body
- Failure description when a request does not return an HTTP response
- Request duration in milliseconds

## Default Output

`ConsoleNetworkLogger` prints a formatted entry for each event, which makes it easy to inspect traffic while developing. Sensitive headers such as `Authorization`, cookies, and API keys are redacted before entries are emitted.

## Integration

`URLSessionNetworkClient` uses `ConsoleNetworkLogger` by default. Pass a custom `NetworkLogging` implementation to capture entries elsewhere, or pass `nil` to disable logging. When logging is enabled, the client emits:

- one request log before `URLSession` starts
- one response log after a valid `HTTPURLResponse`
- one failure log when execution throws before a response is returned
