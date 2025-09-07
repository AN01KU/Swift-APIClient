import Foundation

/// Main API namespace containing all core types and protocols
public enum BaseAPI {

    // MARK: - Type Aliases

    public typealias APIURLResult = Result<HTTPURLResponse, APIError>
    public typealias APIResult<T> = Result<APIResponse<T>, APIError>
    public typealias APIResponse<T> = (data: T, response: HTTPURLResponse)

    // MARK: - Protocols

    /// Protocol defining API endpoint requirements
    public protocol APIEndpoint: Equatable {
        var url: URL { get }
        var stringValue: String { get }
        var authHeader: [String: String]? { get }
    }

    /// Protocol for logging API client operations
    public protocol APIClientLoggingProtocol {
        func info(_ value: String)
        func debug(_ value: String)
        func error(_ value: String)
        func warn(_ value: String)
    }

    /// Protocol for analytics tracking of API operations
    public protocol APIAnalytics {
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
        case missingAuthHeader
        case encodingFailed
        case networkError(String)
        case invalidResponse(response: URLResponse)
        case serverError(response: HTTPURLResponse, code: Int, requestID: String)
        case decodingFailed(response: HTTPURLResponse, error: String)
        case unknown

        public var errorDescription: String? {
            switch self {
            case .missingAuthHeader:
                return "Authentication header is missing"
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
            case .missingAuthHeader, .encodingFailed, .decodingFailed:
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
