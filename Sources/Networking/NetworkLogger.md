# Network Logger

`NetworkLog` models request, response, and failure events emitted by `URLSessionNetworkClient`.

## What It Captures

- HTTP method and URL
- Request headers and body
- Response status code, headers, and body
- Failure description when a request does not return an HTTP response
- Request duration in milliseconds

## Default Output

`ConsoleNetworkLogger` prints a formatted entry for each event, which makes it easy to inspect traffic while developing.

## Integration

`URLSessionNetworkClient` accepts a `NetworkLogging` implementation through its initializer. When a logger is supplied, the client emits:

- one request log before `URLSession` starts
- one response log after a valid `HTTPURLResponse`
- one failure log when execution throws before a response is returned
