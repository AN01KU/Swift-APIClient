import Foundation

extension BaseAPI {

    /// Comprehensive error enum for API operations
    public enum APIError: Error, LocalizedError {
        case encodingFailed
        case networkError(URLError)
        case invalidResponse(response: URLResponse)
        case serverError(response: HTTPURLResponse, code: Int, requestID: String)
        case decodingFailed(response: HTTPURLResponse, error: String)
        case unknown

        public var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode request body"
            case .networkError(let urlError):
                return "Network error: \(urlError.localizedDescription)"
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
}
