# APIClient

A type-safe, async/await HTTP client for Swift. Built on `URLSession`, designed to be subclassed or composed — not wrapped in another layer.

## Requirements

- Swift 5.10+
- macOS 12+ / iOS 15+

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/yourusername/APIClient.git", from: "1.0.0")
]
```

## Overview

The package is namespaced under `BaseAPI` to avoid polluting the global scope. The core types are:

| Type | Role |
|------|------|
| `BaseAPI.APIEndpoint` | Protocol your endpoint enum conforms to |
| `BaseAPI.BaseAPIClient<Endpoint>` | The generic client — instantiate or subclass |
| `BaseAPI.RequestBuilder<Endpoint>` | Fluent builder for one-off request customisation |
| `BaseAPI.RequestInterceptor` | Mutate outgoing requests; optionally retry on failure |
| `BaseAPI.ResponseValidator` | Validate responses before decoding |
| `BaseAPI.RequestEventMonitor` | Observe request lifecycle events |

## Quick Start

### 1. Define endpoints

```swift
enum GitHubAPI: BaseAPI.APIEndpoint {
    case user(login: String)
    case repos(login: String)

    var baseURL: URL { URL(string: "https://api.github.com")! }

    var path: String {
        switch self {
        case .user(let login):  return "/users/\(login)"
        case .repos(let login): return "/users/\(login)/repos"
        }
    }

    var headers: [String: String]? {
        ["Accept": "application/vnd.github+json"]
    }

    var queryParameters: [String: String]? { nil }
}
```

The default `url` implementation on `APIEndpoint` constructs the final URL from `baseURL + path + queryParameters`. Override it only if you need non-standard URL construction.

### 2. Create a client

```swift
let client = BaseAPI.BaseAPIClient<GitHubAPI>()
```

### 3. Make requests

```swift
struct GitHubUser: Decodable {
    let login: String
    let publicRepos: Int
}

// Decoded response
let (user, httpResponse): BaseAPI.APIResponse<GitHubUser> = try await client.get(.user(login: "torvalds"))

// Body-less response (returns HTTPURLResponse)
let response: HTTPURLResponse = try await client.delete(.user(login: "torvalds"))
```

`APIResponse<T>` is a named tuple: `(data: T, response: HTTPURLResponse)`.

## HTTP Methods

The shorthand methods on `BaseAPIClient` cover the common cases:

```swift
// GET — decoded body
let (user, _): BaseAPI.APIResponse<User> = try await client.get(.profile)

// POST — no response body
let http: HTTPURLResponse = try await client.post(.users, body: newUser)

// POST — decoded response body
let (created, _): BaseAPI.APIResponse<User> = try await client.post(.users, body: newUser)

// PUT / PATCH — returns HTTPURLResponse
let http: HTTPURLResponse = try await client.put(.user(id: "1"), body: update)
let http: HTTPURLResponse = try await client.patch(.user(id: "1"), body: patch)

// DELETE — returns HTTPURLResponse
let http: HTTPURLResponse = try await client.delete(.user(id: "1"))

// DELETE — decoded response body
let (body, _): BaseAPI.APIResponse<DeleteResult> = try await client.delete(.user(id: "1"))

// Raw Data body
let (result, _): BaseAPI.APIResponse<Result> = try await client.post(.ingest, rawBody: data)

// Multipart upload
let http: HTTPURLResponse = try await client.multipartUpload(
    .upload,
    method: .post,
    data: BaseAPI.MultipartData(fileKeyName: "file", fileURLs: [fileURL])
)
```

## RequestBuilder

For anything beyond the shorthand methods, use `client.request(_:)` to get a fluent builder:

```swift
// Custom headers, timeout, and per-request validator
let (raw, _): BaseAPI.APIResponse<Data> = try await client
    .request(.download(id: "abc"))
    .headers(["X-Request-ID": UUID().uuidString])
    .timeout(60)
    .validators([BaseAPI.AcceptedStatusCodesValidator([200, 304])])
    .responseData()

// Form-encoded body (e.g. OAuth token endpoint)
let (token, _): BaseAPI.APIResponse<TokenResponse> = try await client
    .request(.token)
    .method(.post)
    .body(form: ["grant_type": "client_credentials", "scope": "read"])
    .response()
```

Available terminal methods on `RequestBuilder`:

| Method | Returns |
|--------|---------|
| `.response()` | `APIResponse<T>` — decoded body |
| `.responseURL()` | `HTTPURLResponse` — ignores body |
| `.responseData()` | `APIResponse<Data>` — raw bytes |
| `.download()` | `AsyncThrowingStream<DownloadProgress, Error>` |

## Interceptors

Interceptors run before every request. Use them for auth header injection, token refresh, signing, etc.

```swift
struct BearerTokenInterceptor: BaseAPI.RequestInterceptor {
    let tokenStore: TokenStore

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var r = request
        let token = try await tokenStore.validToken()
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
}

let client = BaseAPI.BaseAPIClient<MyAPI>(
    interceptors: [BearerTokenInterceptor(tokenStore: session)]
)
```

Multiple interceptors are applied left-to-right. For retry logic, use the built-in `RetryPolicy`:

```swift
let client = BaseAPI.BaseAPIClient<MyAPI>(
    interceptors: [
        BearerTokenInterceptor(tokenStore: session),
        BaseAPI.RetryPolicy(
            maxAttempts: 3,
            backoff: .exponential(base: 1, multiplier: 2, maxDelay: 30),
            retryableStatusCodes: [429, 500, 502, 503, 504]
        )
    ]
)
```

`BackoffStrategy` options: `.none`, `.constant(_:)`, `.exponential(base:multiplier:maxDelay:)`.

## Response Validators

Validators run after a response is received but before the body is decoded. Throw to reject the response.

The default is `StatusCodeValidator`, which accepts 2xx and throws `APIError.serverError` for anything else.

Supply a custom set to override per-client or per-request:

```swift
// Client level — accept only 200 and 201
let client = BaseAPI.BaseAPIClient<MyAPI>(
    validators: [BaseAPI.AcceptedStatusCodesValidator([200, 201])]
)

// Request level — override just for this call
let (data, _) = try await client
    .request(.cached)
    .validators([BaseAPI.AcceptedStatusCodesValidator([200, 304])])
    .responseData()
```

## Event Monitors

Implement `RequestEventMonitor` to observe the request lifecycle. All methods have default no-op implementations — override only what you need.

```swift
struct MetricsMonitor: BaseAPI.RequestEventMonitor {
    func requestDidFinish(
        _ request: URLRequest, endpoint: String, method: String,
        response: HTTPURLResponse, duration: TimeInterval
    ) {
        Analytics.record(endpoint: endpoint, statusCode: response.statusCode, duration: duration)
    }

    func requestDidFail(
        _ request: URLRequest, endpoint: String, method: String,
        error: BaseAPI.APIError, duration: TimeInterval
    ) {
        Analytics.recordError(endpoint: endpoint, error: error, duration: duration)
    }
}

let client = BaseAPI.BaseAPIClient<MyAPI>(
    eventMonitors: [MetricsMonitor()]
)
```

## Downloads with Progress

```swift
for try await progress in client.download(.file(id: "report.pdf")) {
    if let file = progress.data {
        try save(file)
    } else {
        updateUI(fraction: progress.fraction ?? 0)
    }
}
```

`DownloadProgress` provides `bytesReceived`, `totalBytesExpected`, `fraction` (nil when `Content-Length` is absent), and `data` (non-nil only on the final event).

The builder variant lets you add headers or other modifiers:

```swift
let stream = client
    .request(.file(id: "report.pdf"))
    .headers(["Authorization": "Bearer \(token)"])
    .download()
```

## Error Handling

All methods throw `BaseAPI.APIError`:

```swift
public enum APIError: Error {
    case encodingFailed
    case networkError(String)
    case invalidResponse(response: URLResponse)
    case serverError(response: HTTPURLResponse, code: Int, requestID: String)
    case decodingFailed(response: HTTPURLResponse, error: String)
    case unknown
}
```

`.serverError` carries the `x-request-id` response header when present. Both `.serverError` and `.decodingFailed` expose the original `HTTPURLResponse` via `.getResponse()` for callers that need to inspect headers on failure.

```swift
do {
    let (user, _): BaseAPI.APIResponse<User> = try await client.get(.profile)
} catch let error as BaseAPI.APIError {
    switch error {
    case .serverError(let response, let code, let requestID):
        logger.error("HTTP \(code), request-id: \(requestID)")
    case .decodingFailed(let response, let description):
        logger.error("Decode failed for \(response.url?.path ?? ""): \(description)")
    case .networkError(let message):
        logger.error("Network: \(message)")
    default:
        break
    }
}
```

## Unauthorized Handling

Pass an `unauthorizedHandler` to be called synchronously on any 401 before the error is thrown — useful for triggering a logout or a token refresh flow that operates outside the interceptor chain:

```swift
let client = BaseAPI.BaseAPIClient<MyAPI>(
    unauthorizedHandler: { endpoint in
        SessionManager.shared.logout()
    }
)
```

## Subclassing

`BaseAPIClient` is `open`. Subclass to add domain-specific convenience methods:

```swift
final class GitHubClient: BaseAPI.BaseAPIClient<GitHubAPI> {
    func currentUser() async throws -> GitHubUser {
        try await get(.user(login: "me")).data
    }

    func createRepo(name: String, private: Bool) async throws -> HTTPURLResponse {
        try await post(.repos, body: CreateRepoRequest(name: name, isPrivate: `private`))
    }
}
```

## Testing

The client uses standard `URLSession`, so intercept at the `URLProtocol` level — no wrapper or interface needed:

```swift
class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Data, HTTPURLResponse))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { return }
        let (data, response) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// In your test
let config = URLSessionConfiguration.ephemeral
config.protocolClasses = [MockURLProtocol.self]
let client = BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: config)
```

## Development

```bash
swift build
swift test
swift-format -i ./Sources ./Tests --recursive
```

## License

MIT. See [LICENSE](LICENSE).
