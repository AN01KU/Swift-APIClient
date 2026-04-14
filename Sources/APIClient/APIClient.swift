import Foundation

extension BaseAPI {

    /// Generic HTTP API client.
    ///
    /// Parameterized on a concrete ``APIEndpoint`` type. Subclass or instantiate directly.
    /// All network execution is delegated to ``RequestExecution``.
    ///
    /// `@unchecked Sendable` because `JSONEncoder` and `JSONDecoder` lack `Sendable` conformance,
    /// though all stored properties are set once at init and never mutated thereafter.
    open class BaseAPIClient<Endpoint: APIEndpoint>: @unchecked Sendable {

        // MARK: - Properties

        let session: URLSession
        let encoder: JSONEncoder
        let decoder: JSONDecoder
        let interceptorChain: InterceptorChain
        let validators: [any ResponseValidator]
        let eventMonitor: EventMonitorGroup
        let logger: (any APIClientLoggingProtocol)?
        let unauthorizedHandler: (@Sendable (Endpoint) -> Void)?

        // MARK: - Initialization

        /// Create a client with an ordered list of interceptors, response validators, and event monitors.
        ///
        /// - Parameters:
        ///   - interceptors: Applied left-to-right on every outgoing request.
        ///   - validators: Run in order after each response is received; first failure throws.
        ///     Defaults to ``StatusCodeValidator`` (accepts 2xx only).
        ///   - eventMonitors: Receive lifecycle events (start, retry, finish, fail) for every request.
        public init(
            sessionConfiguration: URLSessionConfiguration = .default,
            encoder: JSONEncoder = JSONEncoder(),
            decoder: JSONDecoder = JSONDecoder(),
            interceptors: [any RequestInterceptor] = [],
            validators: [any ResponseValidator] = [StatusCodeValidator()],
            eventMonitors: [any RequestEventMonitor] = [],
            logger: (any APIClientLoggingProtocol)? = nil,
            unauthorizedHandler: (@Sendable (Endpoint) -> Void)? = nil
        ) {
            self.session = URLSession(configuration: sessionConfiguration)
            self.encoder = encoder
            self.decoder = decoder
            self.interceptorChain = InterceptorChain(interceptors)
            self.validators = validators
            self.eventMonitor = EventMonitorGroup(eventMonitors)
            self.logger = logger
            self.unauthorizedHandler = unauthorizedHandler
        }

        /// Convenience initialiser for a single interceptor (backwards-compatible callsite).
        public convenience init(
            sessionConfiguration: URLSessionConfiguration = .default,
            encoder: JSONEncoder = JSONEncoder(),
            decoder: JSONDecoder = JSONDecoder(),
            interceptor: (any RequestInterceptor)?,
            validators: [any ResponseValidator] = [StatusCodeValidator()],
            eventMonitors: [any RequestEventMonitor] = [],
            logger: (any APIClientLoggingProtocol)? = nil,
            unauthorizedHandler: (@Sendable (Endpoint) -> Void)? = nil
        ) {
            self.init(
                sessionConfiguration: sessionConfiguration,
                encoder: encoder,
                decoder: decoder,
                interceptors: interceptor.map { [$0] } ?? [],
                validators: validators,
                eventMonitors: eventMonitors,
                logger: logger,
                unauthorizedHandler: unauthorizedHandler
            )
        }

        // MARK: - GET

        public func get<Response: Decodable>(_ endpoint: Endpoint) async throws -> APIResponse<Response> {
            try await request(endpoint).response()
        }

        // MARK: - POST

        public func post<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.post).body(body).responseURL()
        }

        public func post<Request: Encodable, Response: Decodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.post).body(body).response()
        }

        // MARK: - PUT

        public func put<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.put).body(body).responseURL()
        }

        // MARK: - PATCH

        public func patch<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.patch).body(body).responseURL()
        }

        // MARK: - DELETE

        public func delete(_ endpoint: Endpoint) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.delete).responseURL()
        }

        public func delete<Response: Decodable>(_ endpoint: Endpoint) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.delete).response()
        }

        // MARK: - Multipart Upload

        @available(*, deprecated, message: "Use request(_:).method(_:).body(multipart:).responseURL() instead.")
        public func multipartUpload(
            _ endpoint: Endpoint,
            method: BaseAPI.HTTPMethod,
            form: MultipartFormData
        ) async throws -> HTTPURLResponse {
            var builder = request(endpoint).method(method)
            builder.body = .multipart(form)
            return try await builder.responseURL()
        }

        // MARK: - Raw Data Body

        public func post<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.post).body(raw: rawBody).response()
        }

        public func put<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.put).body(raw: rawBody).response()
        }

        public func patch<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.patch).body(raw: rawBody).response()
        }

        // MARK: - RequestBuilder Entry Point

        /// Create a ``RequestBuilder`` for the given endpoint.
        public func request(_ endpoint: Endpoint) -> RequestBuilder<Endpoint> {
            RequestBuilder(endpoint: endpoint, client: self)
        }

        // MARK: - Download

        /// Stream download progress for the given endpoint.
        ///
        /// Returns an `AsyncThrowingStream` that emits one ``DownloadProgress`` event per
        /// received chunk. The final event has a non-nil `data` property containing the
        /// complete response body.
        public func download(_ endpoint: Endpoint) -> AsyncThrowingStream<DownloadProgress, Error> {
            executeDownload(RequestBuilder(endpoint: endpoint, client: self))
        }
    }
}
