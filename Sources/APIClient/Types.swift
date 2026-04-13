import Foundation

/// Main API namespace containing all core types and protocols
public enum BaseAPI {

    // MARK: - Type Aliases

    public typealias APIResponse<T> = (data: T, response: HTTPURLResponse)

    // MARK: - Data Structures

    /// Container for multipart form data uploads
    public struct MultipartData: Sendable {
        public let parameters: [String: String]?
        public let fileKeyName: String
        public let fileURLs: [URL]?

        public init(
            parameters: [String: String]? = nil,
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
    public struct EmptyResponse: Codable, Sendable {
        public init() {}
    }
}
