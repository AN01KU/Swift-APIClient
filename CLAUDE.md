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

This is a Swift Package (`Sources/APIClient`) providing a generic HTTP client library. Everything lives under a single `BaseAPI` enum namespace to avoid polluting the global scope.

### Core type flow

1. **`BaseAPI.APIEndpoint`** (protocol in `APITypes.swift`) — callers define their API surface as an enum conforming to this. Provides `baseURL`, `path`, `headers`, `queryParameters`. The default extension computes `var url: URL` by combining these.

2. **`BaseAPI.BaseAPIClient<Endpoint>`** (class in `APIClient.swift`) — the generic client, parameterized on a concrete `APIEndpoint`. Callers subclass or instantiate this directly. All HTTP methods come in two flavors:
   - `async throws` — returns `APIResponse<T>` (a typealias for `(data: T, response: HTTPURLResponse)`) or `HTTPURLResponse` for body-less responses
   - callback (`then:`) — wraps the async version in a `Task`, calls back with `Result`

3. **`BaseAPI.RequestInterceptor`** (protocol in `APITypes.swift`) — injected at init, called via `adapt(_:)` before every request. Use for auth headers, token refresh, etc.

4. **`Extensions.swift`** — internal helpers on `URLRequest` (`addJSONHeaders`, `addJSONBody`, `addMultipartData`) and `Data` (`decode`). These are not public API.

### Key design decisions

- **`BaseAPIClient` is `open`**, so callers can subclass to add domain-specific methods.
- **Strict concurrency** is enabled (`StrictConcurrency` experimental feature). All protocols are `Sendable`. `BaseAPIClient` is `@unchecked Sendable` because its stored properties are set once at init.
- **`EmptyResponse`** is used as a sentinel for requests/responses with no body — e.g., POST that returns 204.
- **`unauthorizedHandler`** is called synchronously on 401 before throwing; use it to trigger logout or token refresh flows.
- Analytics (`APIAnalytics`) and logging (`APIClientLoggingProtocol`) are optional and injected at init. The concrete `APIClientLogger` just `print()`s with emoji prefixes.

### Response error model

`APIError` cases carry associated data:
- `.serverError(response:code:requestID:)` — non-2xx; `requestID` comes from the `x-request-id` response header
- `.decodingFailed(response:error:)` — JSON decode failure, includes the original `HTTPURLResponse`
- Both expose the response via `.getResponse()` extension for callers that need to inspect headers on failure

### Test approach

Tests (`Tests/APIClientTests/APIClientTests.swift`) use Swift Testing (`import Testing`, `@Test`). Mocks are local to the test file: `MockEndpoint`, `MockLogger`, `MockInterceptor`, `FailingInterceptor`, `MockAnalytics`. Tests rely on `URLProtocol` subclassing to intercept network calls — no real network required.

## Code style

- Follow Apple's Swift API Design Guidelines
- Use `guard let`/`if let` — no force unwraps
- Access control: `private` internals, `public` API surface, `open` for subclassable types
- Commit messages: imperative tone, one-line summary ≤50 chars, atomic per change
