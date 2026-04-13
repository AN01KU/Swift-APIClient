import Foundation

/// APIClient-specific logger that conforms to APIClientLoggingProtocol
/// Simple implementation that prints logs to console
public final class APIClientLogger: BaseAPI.APIClientLoggingProtocol, Sendable {

    /// Initialize the logger
    public init() {}

    // MARK: - APIClientLoggingProtocol Implementation

    public func info(_ value: String) {
        print("🔷 [APIClient INFO] \(value)")
    }

    public func debug(_ value: String) {
        print("🚀 [APIClient DEBUG] \(value)")
    }

    public func error(_ value: String) {
        print("❌ [APIClient ERROR] \(value)")
    }

    public func warn(_ value: String) {
        print("🔶 [APIClient WARN] \(value)")
    }
}
