# HTTPRequest

`HTTPRequest` now resolves URLs using only the request payload and a client `baseURL`.

## Versioning behavior

- `apiVersion` is optional and belongs to each request type.
- when `apiVersion` is set, its path component (for example `v1`) is prefixed to the request path.
- when the request path already starts with the same version component, no duplicate prefix is added.
- when `apiVersion` is `nil`, the path is used as-is.

This keeps API version ownership at the endpoint definition level instead of a global client configuration.
