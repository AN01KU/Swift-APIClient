import Foundation

extension BaseAPI {

    /// Fans out lifecycle events to multiple ``RequestEventMonitor`` instances.
    ///
    /// Pass it to ``BaseAPIClient``'s `eventMonitors` parameter to compose monitors:
    /// ```swift
    /// BaseAPI.BaseAPIClient<MyAPI>(
    ///     eventMonitors: [LatencyMonitor(), AnalyticsMonitor()]
    /// )
    /// ```
    public struct EventMonitorGroup: RequestEventMonitor {
        private let monitors: [any RequestEventMonitor]

        public init(_ monitors: [any RequestEventMonitor]) {
            self.monitors = monitors
        }

        public func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {
            monitors.forEach { $0.requestDidStart(request, endpoint: endpoint, method: method) }
        }

        public func requestWillRetry(
            _ request: URLRequest, endpoint: String, method: String,
            attemptCount: Int, delay: TimeInterval
        ) {
            monitors.forEach {
                $0.requestWillRetry(
                    request, endpoint: endpoint, method: method,
                    attemptCount: attemptCount, delay: delay)
            }
        }

        public func requestDidFinish(
            _ request: URLRequest, endpoint: String, method: String,
            response: HTTPURLResponse, duration: TimeInterval
        ) {
            monitors.forEach {
                $0.requestDidFinish(
                    request, endpoint: endpoint, method: method,
                    response: response, duration: duration)
            }
        }

        public func requestDidFail(
            _ request: URLRequest, endpoint: String, method: String,
            error: APIError, duration: TimeInterval
        ) {
            monitors.forEach {
                $0.requestDidFail(
                    request, endpoint: endpoint, method: method,
                    error: error, duration: duration)
            }
        }
    }
}
