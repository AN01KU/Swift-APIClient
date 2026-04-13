import Foundation

extension BaseAPI {

    public enum HTTPMethod: String, CaseIterable, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
        case head = "HEAD"
        case options = "OPTIONS"
    }
}
