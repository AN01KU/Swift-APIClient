import Foundation

extension BaseAPI {

    /// Protocol defining API endpoint requirements
    public protocol APIEndpoint: Equatable, Sendable {
        /// Base URL for the API (e.g., "https://api.example.com")
        var baseURL: URL { get }
        /// Path component appended to baseURL (e.g., "/users/123")
        var path: String { get }
        /// Endpoint-specific headers (merged into the request)
        var headers: [String: String]? { get }
        /// Query parameters appended to the URL
        var queryParameters: [String: String]? { get }
    }

    /// Protocol for intercepting and adapting outgoing requests, and optionally retrying them.
    ///
    /// - `adapt` is called before every attempt, allowing header injection, token refresh, etc.
    /// - `retry` is called after a failed attempt; return `.retry(delay:)` to schedule another attempt.
    ///
    /// Most interceptors only need `adapt` — the default `retry` implementation returns `.doNotRetry`.
    public protocol RequestInterceptor: Sendable {
        /// Mutate or replace the outgoing request before it is sent.
        func adapt(_ request: URLRequest) async throws -> URLRequest
        /// Decide whether to retry after `error` on attempt number `attemptCount` (1-based).
        func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> RetryDecision
    }

    /// Protocol for validating HTTP responses before decoding.
    ///
    /// Validators run after a response is received but before the body is decoded.
    /// Throw an ``APIError`` (or any `Error`) to reject the response.
    ///
    /// Multiple validators can be composed by passing them to ``BaseAPIClient``'s `validators` parameter.
    /// They are evaluated in order; the first one that throws stops the chain.
    public protocol ResponseValidator: Sendable {
        func validate(_ response: HTTPURLResponse, data: Data, for request: URLRequest) throws
    }

    /// Protocol for logging API client operations
    public protocol APIClientLoggingProtocol: Sendable {
        func info(_ value: String)
        func debug(_ value: String)
        func error(_ value: String)
        func warn(_ value: String)
    }


    /// Observer protocol for fine-grained request lifecycle events.
    ///
    /// Every method has a default no-op implementation — conform and override only the
    /// events you care about. Multiple monitors can be composed with ``EventMonitorGroup``.
    public protocol RequestEventMonitor: Sendable {
        /// Called once, just before the first network attempt.
        func requestDidStart(_ request: URLRequest, endpoint: String, method: String)

        /// Called before each retry attempt (not before the first attempt).
        func requestWillRetry(
            _ request: URLRequest, endpoint: String, method: String,
            attemptCount: Int, delay: TimeInterval)

        /// Called when a response is successfully received and validated.
        func requestDidFinish(
            _ request: URLRequest, endpoint: String, method: String,
            response: HTTPURLResponse, duration: TimeInterval)

        /// Called when the request fails without being retried further.
        func requestDidFail(
            _ request: URLRequest, endpoint: String, method: String,
            error: APIError, duration: TimeInterval)
    }

    /// Decision returned by an interceptor's retry handler.
    public enum RetryDecision: Sendable {
        /// Retry the request after the given delay (in seconds). Use 0 for immediate retry.
        case retry(delay: TimeInterval)
        /// Do not retry; propagate the error to the caller.
        case doNotRetry
    }
}

// MARK: - RequestEventMonitor Defaults

extension BaseAPI.RequestEventMonitor {
    public func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {}
    public func requestWillRetry(
        _ request: URLRequest, endpoint: String, method: String,
        attemptCount: Int, delay: TimeInterval
    ) {}
    public func requestDidFinish(
        _ request: URLRequest, endpoint: String, method: String,
        response: HTTPURLResponse, duration: TimeInterval
    ) {}
    public func requestDidFail(
        _ request: URLRequest, endpoint: String, method: String,
        error: BaseAPI.APIError, duration: TimeInterval
    ) {}
}

// MARK: - RequestInterceptor Defaults

extension BaseAPI.RequestInterceptor {
    /// Default: never retry. Override to add retry logic.
    public func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> BaseAPI.RetryDecision {
        .doNotRetry
    }
}

// MARK: - APIEndpoint Defaults

extension BaseAPI.APIEndpoint {
    /// Constructed URL from baseURL + path + queryParameters
    public var url: URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if let queryParameters, !queryParameters.isEmpty {
            components?.queryItems =
                queryParameters
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components?.url ?? baseURL.appendingPathComponent(path)
    }

    /// String representation for logging
    public var stringValue: String { path }

    /// Default: no endpoint-specific headers
    public var headers: [String: String]? { nil }

    /// Default: no query parameters
    public var queryParameters: [String: String]? { nil }
}
