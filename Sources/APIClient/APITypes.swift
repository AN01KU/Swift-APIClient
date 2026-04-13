import Foundation

/// Main API namespace containing all core types and protocols
public enum BaseAPI {

    // MARK: - Type Aliases

    public typealias APIURLResult = Result<HTTPURLResponse, APIError>
    public typealias APIResult<T> = Result<APIResponse<T>, APIError>
    public typealias APIResponse<T> = (data: T, response: HTTPURLResponse)

    // MARK: - Protocols

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

    /// Decision returned by an interceptor's retry handler.
    public enum RetryDecision: Sendable {
        /// Retry the request after the given delay (in seconds). Use 0 for immediate retry.
        case retry(delay: TimeInterval)
        /// Do not retry; propagate the error to the caller.
        case doNotRetry
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

    /// Protocol for analytics tracking of API operations
    @available(*, deprecated, renamed: "RequestEventMonitor", message: "Use RequestEventMonitor for richer lifecycle events.")
    public protocol APIAnalytics: Sendable {
        func addAnalytics(
            endpoint: String,
            method: String,
            startTime: Date,
            endTime: Date,
            success: Bool,
            statusCode: Int?,
            error: String?
        )
    }

    /// Observer protocol for fine-grained request lifecycle events.
    ///
    /// Every method has a default no-op implementation — conform and override only the
    /// events you care about. Multiple monitors can be composed with ``EventMonitorGroup``.
    ///
    /// Example — measuring latency:
    /// ```swift
    /// struct LatencyMonitor: BaseAPI.RequestEventMonitor {
    ///     func requestDidFinish(_ request: URLRequest, endpoint: String, method: String,
    ///                           response: HTTPURLResponse, duration: TimeInterval) {
    ///         print("\(method) \(endpoint) → \(response.statusCode) in \(duration * 1000)ms")
    ///     }
    /// }
    /// ```
    public protocol RequestEventMonitor: Sendable {
        /// Called once, just before the first network attempt.
        func requestDidStart(_ request: URLRequest, endpoint: String, method: String)

        /// Called before each retry attempt (not before the first attempt).
        func requestWillRetry(_ request: URLRequest, endpoint: String, method: String,
                              attemptCount: Int, delay: TimeInterval)

        /// Called when a response is successfully received and validated.
        func requestDidFinish(_ request: URLRequest, endpoint: String, method: String,
                              response: HTTPURLResponse, duration: TimeInterval)

        /// Called when the request fails without being retried further.
        func requestDidFail(_ request: URLRequest, endpoint: String, method: String,
                            error: APIError, duration: TimeInterval)
    }

    // MARK: - Error Types

    /// Comprehensive error enum for API operations
    public enum APIError: Error, LocalizedError {
        case encodingFailed
        case networkError(String)
        case invalidResponse(response: URLResponse)
        case serverError(response: HTTPURLResponse, code: Int, requestID: String)
        case decodingFailed(response: HTTPURLResponse, error: String)
        case unknown

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode request body"
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidResponse:
                return "Invalid response received"
            case .serverError(_, let code, let requestID):
                return "Server error \(code), Request ID: \(requestID)"
            case .decodingFailed(_, let message):
                return "Failed to decode response: \(message)"
            case .unknown:
                return "Unknown error occurred"
            }
        }

        public var isClientError: Bool {
            switch self {
            case .encodingFailed, .decodingFailed:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Data Structures

    /// Container for multipart form data uploads
    public struct MultipartData {
        public let parameters: [String: AnyObject]?
        public let fileKeyName: String
        public let fileURLs: [URL]?

        public init(
            parameters: [String: AnyObject]? = nil,
            fileKeyName: String,
            fileURLs: [URL]? = nil
        ) {
            self.parameters = parameters
            self.fileKeyName = fileKeyName
            self.fileURLs = fileURLs
        }

        public var stringValue: String {
            var components: [String] = []

            if let parameters = parameters, !parameters.isEmpty {
                let paramStrings = parameters.map { "\($0.key): \($0.value)" }
                components.append("parameters: [\(paramStrings.joined(separator: ", "))]")
            }

            components.append("fileKeyName: \(fileKeyName)")

            if let fileURLs = fileURLs, !fileURLs.isEmpty {
                let fileNames = fileURLs.map { $0.lastPathComponent }
                components.append("files: [\(fileNames.joined(separator: ", "))]")
            }

            return components.joined(separator: ", ")
        }
    }

    /// Empty response type for requests that don't return data
    public struct EmptyResponse: Codable {
        public init() {}
    }
}

// MARK: - RequestEventMonitor Defaults

extension BaseAPI.RequestEventMonitor {
    public func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {}
    public func requestWillRetry(_ request: URLRequest, endpoint: String, method: String,
                                 attemptCount: Int, delay: TimeInterval) {}
    public func requestDidFinish(_ request: URLRequest, endpoint: String, method: String,
                                 response: HTTPURLResponse, duration: TimeInterval) {}
    public func requestDidFail(_ request: URLRequest, endpoint: String, method: String,
                               error: BaseAPI.APIError, duration: TimeInterval) {}
}

// MARK: - EventMonitorGroup

extension BaseAPI {
    /// Fans out lifecycle events to multiple ``RequestEventMonitor`` instances.
    ///
    /// Pass it to ``BaseAPIClient``'s `eventMonitors` parameter to compose monitors:
    /// ```swift
    /// BaseAPI.BaseAPIClient<MyAPI>(
    ///     eventMonitors: [LatencyMonitor(), AnalyticsMonitor()]
    /// )
    /// ```
    public struct EventMonitorGroup: RequestEventMonitor {
        private let monitors: [any RequestEventMonitor]

        public init(_ monitors: [any RequestEventMonitor]) {
            self.monitors = monitors
        }

        public func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {
            monitors.forEach { $0.requestDidStart(request, endpoint: endpoint, method: method) }
        }

        public func requestWillRetry(_ request: URLRequest, endpoint: String, method: String,
                                     attemptCount: Int, delay: TimeInterval) {
            monitors.forEach {
                $0.requestWillRetry(request, endpoint: endpoint, method: method,
                                    attemptCount: attemptCount, delay: delay)
            }
        }

        public func requestDidFinish(_ request: URLRequest, endpoint: String, method: String,
                                     response: HTTPURLResponse, duration: TimeInterval) {
            monitors.forEach {
                $0.requestDidFinish(request, endpoint: endpoint, method: method,
                                    response: response, duration: duration)
            }
        }

        public func requestDidFail(_ request: URLRequest, endpoint: String, method: String,
                                   error: APIError, duration: TimeInterval) {
            monitors.forEach {
                $0.requestDidFail(request, endpoint: endpoint, method: method,
                                  error: error, duration: duration)
            }
        }
    }
}

// MARK: - RequestInterceptor Defaults

extension BaseAPI.RequestInterceptor {
    /// Default: never retry. Override to add retry logic.
    public func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> BaseAPI.RetryDecision {
        .doNotRetry
    }
}

// MARK: - InterceptorChain

extension BaseAPI {
    /// Composes multiple ``RequestInterceptor`` values into a single pipeline.
    ///
    /// `adapt` calls are applied left-to-right (first interceptor runs first).
    /// `retry` asks each interceptor in order; the first `.retry` decision wins.
    public struct InterceptorChain: RequestInterceptor {
        private let interceptors: [any RequestInterceptor]

        public init(_ interceptors: [any RequestInterceptor]) {
            self.interceptors = interceptors
        }

        public func adapt(_ request: URLRequest) async throws -> URLRequest {
            var current = request
            for interceptor in interceptors {
                current = try await interceptor.adapt(current)
            }
            return current
        }

        public func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> RetryDecision {
            for interceptor in interceptors {
                let decision = await interceptor.retry(request, dueTo: error, attemptCount: attemptCount)
                if case .retry = decision { return decision }
            }
            return .doNotRetry
        }
    }
}

// MARK: - RetryPolicy

extension BaseAPI {
    /// Configures the delay between retry attempts.
    public enum BackoffStrategy: Sendable {
        /// No delay between attempts.
        case none
        /// Fixed delay between every attempt.
        case constant(TimeInterval)
        /// Delay doubles each attempt: `base * multiplier^(attempt - 1)`, capped at `maxDelay`.
        ///
        /// Example — `base: 1, multiplier: 2, maxDelay: 30`:
        /// attempt 1 → 1s, attempt 2 → 2s, attempt 3 → 4s, attempt 4 → 8s …
        case exponential(base: TimeInterval, multiplier: Double, maxDelay: TimeInterval)

        func delay(for attemptCount: Int) -> TimeInterval {
            switch self {
            case .none:
                return 0
            case .constant(let interval):
                return interval
            case .exponential(let base, let multiplier, let maxDelay):
                let raw = base * pow(multiplier, Double(attemptCount - 1))
                return min(raw, maxDelay)
            }
        }
    }

    /// A built-in ``RequestInterceptor`` that retries failed requests according to a backoff policy.
    ///
    /// Add it to the `interceptors` array when creating a ``BaseAPIClient``:
    /// ```swift
    /// BaseAPI.BaseAPIClient<MyAPI>(
    ///     interceptors: [
    ///         BearerTokenInterceptor(store: session),
    ///         BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .exponential(base: 1, multiplier: 2, maxDelay: 30))
    ///     ]
    /// )
    /// ```
    ///
    /// - `adapt` is a no-op — `RetryPolicy` only acts in `retry`.
    /// - Only retries when `error` is an ``APIError/serverError(_:code:requestID:)`` whose
    ///   status code is in `retryableStatusCodes`, or when it is a network-level error and
    ///   `retryNetworkErrors` is `true`.
    public struct RetryPolicy: RequestInterceptor {
        /// Maximum number of attempts (including the first). Minimum value is 1.
        public let maxAttempts: Int
        /// Delay strategy between attempts.
        public let backoff: BackoffStrategy
        /// HTTP status codes that should trigger a retry. Defaults to `[429, 500, 502, 503, 504]`.
        public let retryableStatusCodes: Set<Int>
        /// When `true`, transient network errors (`.networkError`) also trigger a retry.
        public let retryNetworkErrors: Bool

        public init(
            maxAttempts: Int = 3,
            backoff: BackoffStrategy = .exponential(base: 1, multiplier: 2, maxDelay: 30),
            retryableStatusCodes: Set<Int> = [429, 500, 502, 503, 504],
            retryNetworkErrors: Bool = false
        ) {
            self.maxAttempts = max(1, maxAttempts)
            self.backoff = backoff
            self.retryableStatusCodes = retryableStatusCodes
            self.retryNetworkErrors = retryNetworkErrors
        }

        public func adapt(_ request: URLRequest) async throws -> URLRequest { request }

        public func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> RetryDecision {
            guard attemptCount < maxAttempts else { return .doNotRetry }

            if let apiError = error as? APIError {
                switch apiError {
                case .serverError(_, let code, _) where retryableStatusCodes.contains(code):
                    return .retry(delay: backoff.delay(for: attemptCount))
                case .networkError where retryNetworkErrors:
                    return .retry(delay: backoff.delay(for: attemptCount))
                default:
                    return .doNotRetry
                }
            }
            return .doNotRetry
        }
    }
}

// MARK: - Built-in Response Validators

extension BaseAPI {
    /// Rejects responses whose status code falls outside 200–299.
    ///
    /// On 401 it also fires the client's `unauthorizedHandler` (handled inside `BaseAPIClient`).
    /// This is the default validator used when no explicit `validators` are supplied.
    public struct StatusCodeValidator: ResponseValidator {
        public init() {}

        public func validate(_ response: HTTPURLResponse, data: Data, for request: URLRequest) throws {
            guard (200...299).contains(response.statusCode) else {
                let requestId = response.value(forHTTPHeaderField: "x-request-id") ?? "N/A"
                throw APIError.serverError(
                    response: response,
                    code: response.statusCode,
                    requestID: requestId
                )
            }
        }
    }

    /// Rejects responses whose status code is not in the caller-supplied set.
    ///
    /// Use this when your API uses non-2xx codes for success (e.g. 304 Not Modified).
    public struct AcceptedStatusCodesValidator: ResponseValidator {
        private let accepted: Set<Int>

        /// - Parameter statusCodes: The HTTP status codes that should be treated as success.
        public init(_ statusCodes: Set<Int>) {
            self.accepted = statusCodes
        }

        public func validate(_ response: HTTPURLResponse, data: Data, for request: URLRequest) throws {
            guard accepted.contains(response.statusCode) else {
                let requestId = response.value(forHTTPHeaderField: "x-request-id") ?? "N/A"
                throw APIError.serverError(
                    response: response,
                    code: response.statusCode,
                    requestID: requestId
                )
            }
        }
    }
}

// MARK: - APIError Extensions

extension BaseAPI.APIError {
    public func getResponse() -> HTTPURLResponse? {
        switch self {
        case .serverError(let response, _, _):
            return response
        case .decodingFailed(let response, _):
            return response
        default:
            return nil
        }
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
            components?.queryItems = queryParameters
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
