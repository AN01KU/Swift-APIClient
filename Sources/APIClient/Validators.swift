import Foundation

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
