import Foundation
import os.log

/// Concrete ``BaseAPI.APIClientLoggingProtocol`` implementation backed by `os.Logger`.
///
/// Logs appear in Console.app and `log stream` under the subsystem `APIClient`.
/// Pass a custom `subsystem` and `category` when you need to filter logs per target.
public final class APIClientLogger: BaseAPI.APIClientLoggingProtocol, Sendable {

    private let logger: Logger

    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier for the subsystem (default: `"APIClient"`).
    ///   - category:  Log category for filtering (default: `"Network"`).
    public init(subsystem: String = "APIClient", category: String = "Network") {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    // MARK: - APIClientLoggingProtocol

    public func info(_ value: String) {
        logger.info("\(value, privacy: .public)")
    }

    public func debug(_ value: String) {
        logger.debug("\(value, privacy: .public)")
    }

    public func error(_ value: String) {
        logger.error("\(value, privacy: .public)")
    }

    public func warn(_ value: String) {
        logger.warning("\(value, privacy: .public)")
    }
}
