# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Build
swift build

# Run all tests
swift test

# Run a single test by name
swift test --filter "APIClientTests/testMethodName"

# Format code
swift-format -i ./Sources ./Tests --recursive
```

## Architecture

This is a Swift Package (`Sources/APIClient`) providing a generic HTTP client library. Everything lives under a single `BaseAPI` enum namespace to avoid polluting the global scope. The package targets Swift 6 language mode (strict concurrency enforced at compile time).

### Source files

| File | Contents |
|------|----------|
| `Types.swift` | `BaseAPI` namespace, `APIResponse` typealias, `MultipartFormData`, `EmptyResponse` |
| `Protocols.swift` | `APIEndpoint`, `RequestInterceptor`, `ResponseValidator`, `APIClientLoggingProtocol`, `RequestEventMonitor`, `RetryDecision` |
| `APIClient.swift` | `BaseAPIClient<Endpoint>` — shorthand HTTP methods, entry point for `RequestBuilder` |
| `RequestBuilder.swift` | `RequestBody` enum, `RequestBuilder<Endpoint>` fluent builder and terminal methods |
| `RequestExecution.swift` | `execute`, `executeRaw`, `executeDownload`, `createBaseRequest`, `applyBuilderOverrides`, `runValidators`, `handleRetry` |
| `HTTPMethod.swift` | `HTTPMethod` enum: GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS |
| `APIError.swift` | `APIError` enum |
| `Interceptors.swift` | `InterceptorChain`, `RetryPolicy`, `BackoffStrategy` |
| `Validators.swift` | `StatusCodeValidator`, `AcceptedStatusCodesValidator` |
| `EventMonitor.swift` | `EventMonitorGroup` |
| `APIClientLogger.swift` | Concrete `APIClientLogger` backed by `os.Logger` |
| `Extensions.swift` | Internal helpers: `addJSONHeaders`, `addJSONBody`, `applyMultipart`, `Data.decode`, `formURLEncoded`, `AnyEncodable`, `URLSession.mimeTypeForPath` |
| `Download.swift` | `DownloadProgress` type and `executeDownload` support |

### Core type flow

1. **`BaseAPI.APIEndpoint`** (protocol in `Protocols.swift`) — callers define their API surface as an enum conforming to this. Provides `baseURL`, `path`, `headers`, `queryParameters`. The default extension computes `var url: URL` by combining these.

2. **`BaseAPI.BaseAPIClient<Endpoint>`** (class in `APIClient.swift`) — the generic client, parameterized on a concrete `APIEndpoint`. Callers subclass or instantiate this directly. All HTTP methods return `async throws` — either `APIResponse<T>` (named tuple `(data: T, response: HTTPURLResponse)`) or `HTTPURLResponse` for body-less responses.

3. **`BaseAPI.RequestBuilder<Endpoint>`** (struct in `RequestBuilder.swift`) — fluent builder obtained via `client.request(_:)`. Execution is deferred until a terminal method (`.response()`, `.responseURL()`, `.responseData()`, `.download()`) is called.

4. **`BaseAPI.RequestInterceptor`** (protocol in `Protocols.swift`) — injected at init, called via `adapt(_:)` before every attempt. The `retry(_:dueTo:attemptCount:)` method decides whether to retry after failure.

5. **`BaseAPI.MultipartFormData`** (class in `Types.swift`) — builder for multipart/form-data bodies. Append parts via `append(_:name:)`, `append(fileURL:name:)`, or `append(_:length:name:fileName:mimeType:)`. Used through `RequestBuilder.body(multipart:)`.

### Key design decisions

- **`BaseAPIClient` is `open`**, so callers can subclass to add domain-specific methods.
- **Swift 6 language mode** — strict concurrency is enforced at compile time (not the experimental flag). All protocols are `Sendable`. `BaseAPIClient` is `@unchecked Sendable` because its stored properties are set once at init.
- **`EmptyResponse`** is used as a sentinel for requests/responses with no body — e.g., POST that returns 204.
- **`unauthorizedHandler`** fires after all retry attempts are exhausted on a 401. It does NOT fire during intermediate retry attempts (e.g. token-refresh retries). Moved from the validator layer to `handleRetry` in `RequestExecution.swift`.
- **`MultipartFormData`** has a fixed boundary set at init, so the encoded body is identical across all retry attempts.
- **`APIClientLogger`** uses `os.Logger` (not `print()`). Pass a custom subsystem/category to init.

### Response error model

`APIError` cases carry associated data:
- `.networkError(URLError)` — preserves the underlying `URLError` so callers can inspect `URLError.Code`
- `.serverError(response:code:requestID:)` — non-2xx; `requestID` comes from the `x-request-id` response header
- `.decodingFailed(response:error:)` — JSON decode failure, includes the original `HTTPURLResponse`
- Both `.serverError` and `.decodingFailed` expose the response via `.getResponse()` for callers that need to inspect headers on failure

### Test approach

Tests use Swift Testing (`import Testing`, `@Test`). Test files:
- `Mocks.swift` — `MockEndpoint`, `MockLogger`, `MockInterceptor`, `FailingInterceptor`, `MockAnalytics`, `MockURLProtocol`, `ActorBox<T>`, `UnencodableBody`
- `APIClientTests.swift` — unit tests for types, errors, encoding, validators, interceptors
- `NetworkTests.swift` — network-level tests using `MockURLProtocol` to intercept `URLSession` calls. All suites in this file are `.serialized` to avoid `MockURLProtocol.handler` state bleed.

`MockURLProtocol.handler` is `nonisolated(unsafe) static var` — required for Swift 6 compatibility. Use `ActorBox<T>` (a simple actor wrapper) to safely capture and mutate values inside `@Sendable` closures in tests.

## Code style

- Follow Apple's Swift API Design Guidelines
- Use `guard let`/`if let` — no force unwraps
- Access control: `private` internals, `public` API surface, `open` for subclassable types
- Commit messages: imperative tone, one-line summary ≤50 chars, atomic per change
