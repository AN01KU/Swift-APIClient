import Foundation

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

    // MARK: - BackoffStrategy

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

    // MARK: - RetryPolicy

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
