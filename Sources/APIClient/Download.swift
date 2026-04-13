import Foundation

extension BaseAPI {

    // MARK: - DownloadProgress

    /// A snapshot of download progress emitted by ``BaseAPIClient/download(_:)``
    /// and ``RequestBuilder/download()``.
    ///
    /// The stream emits one event per received chunk. The final event has a non-nil
    /// ``data`` property containing the complete response body. All earlier events
    /// have `data == nil`.
    ///
    /// ```swift
    /// for try await progress in client.download(endpoint) {
    ///     if let file = progress.data {
    ///         // download complete
    ///         saveFile(file)
    ///     } else {
    ///         updateProgressBar(progress.fraction ?? 0)
    ///     }
    /// }
    /// ```
    public struct DownloadProgress: Sendable {
        /// Total bytes received so far (cumulative).
        public let bytesReceived: Int64
        /// Expected total bytes from the `Content-Length` header.
        /// `nil` when the server does not provide `Content-Length`.
        public let totalBytesExpected: Int64?
        /// Download fraction in `0.0 ... 1.0`.
        /// `nil` when ``totalBytesExpected`` is unknown.
        public var fraction: Double? {
            guard let total = totalBytesExpected, total > 0 else { return nil }
            return min(Double(bytesReceived) / Double(total), 1.0)
        }
        /// The complete response body. Non-nil only on the final progress event.
        public let data: Data?
        /// The HTTP response associated with this download. Available on all events.
        public let response: HTTPURLResponse
    }
}
