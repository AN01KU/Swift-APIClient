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

    /// Protocol for logging API client operations
    public protocol APIClientLoggingProtocol: Sendable {
        func info(_ value: String)
        func debug(_ value: String)
        func error(_ value: String)
        func warn(_ value: String)
    }

    /// Protocol for analytics tracking of API operations
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
