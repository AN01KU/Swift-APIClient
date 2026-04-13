import Foundation

extension BaseAPI {

    /// Generic HTTP API client with async/await and callback support.
    ///
    /// Parameterized on a concrete ``APIEndpoint`` type. Subclass or instantiate directly.
    /// All network execution is delegated to ``RequestExecution``.
    open class BaseAPIClient<Endpoint: APIEndpoint>: @unchecked Sendable {

        // MARK: - Properties

        let session: URLSession
        let encoder: JSONEncoder
        let decoder: JSONDecoder
        let interceptorChain: InterceptorChain
        let validators: [any ResponseValidator]
        let eventMonitor: EventMonitorGroup
        @available(*, deprecated, renamed: "eventMonitors")
        let analytics: (any APIAnalytics)?
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
            analytics: (any APIAnalytics)? = nil,
            logger: (any APIClientLoggingProtocol)? = nil,
            unauthorizedHandler: (@Sendable (Endpoint) -> Void)? = nil
        ) {
            self.session = URLSession(configuration: sessionConfiguration)
            self.encoder = encoder
            self.decoder = decoder
            self.interceptorChain = InterceptorChain(interceptors)
            self.validators = validators
            self.eventMonitor = EventMonitorGroup(eventMonitors)
            self.analytics = analytics
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
            analytics: (any APIAnalytics)? = nil,
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
                analytics: analytics,
                logger: logger,
                unauthorizedHandler: unauthorizedHandler
            )
        }

        // MARK: - GET

        public func get<Response: Decodable>(_ endpoint: Endpoint) async throws -> APIResponse<Response> {
            try await request(endpoint).response()
        }

        public func get<Response>(
            _ endpoint: Endpoint,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await get(endpoint)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - POST

        public func post<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.post).body(body).responseURL()
        }

        public func post<Request>(
            _ endpoint: Endpoint,
            body: Request,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    callback(.success(try await self.post(endpoint, body: body) as HTTPURLResponse))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        public func post<Request: Encodable, Response: Decodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.post).body(body).response()
        }

        public func post<Request, Response>(
            _ endpoint: Endpoint,
            body: Request,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable, Request: Encodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await self.post(endpoint, body: body)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - PUT

        public func put<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.put).body(body).responseURL()
        }

        public func put<Request>(
            _ endpoint: Endpoint,
            body: Request,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    callback(.success(try await self.put(endpoint, body: body) as HTTPURLResponse))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - PATCH

        public func patch<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request
        ) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.patch).body(body).responseURL()
        }

        public func patch<Request>(
            _ endpoint: Endpoint,
            body: Request,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    callback(.success(try await self.patch(endpoint, body: body) as HTTPURLResponse))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - DELETE

        public func delete(_ endpoint: Endpoint) async throws -> HTTPURLResponse {
            try await request(endpoint).method(.delete).responseURL()
        }

        public func delete(
            _ endpoint: Endpoint,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) {
            Task {
                do {
                    callback(.success(try await self.delete(endpoint) as HTTPURLResponse))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        public func delete<Response: Decodable>(_ endpoint: Endpoint) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.delete).response()
        }

        public func delete<Response>(
            _ endpoint: Endpoint,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await self.delete(endpoint)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - Multipart Upload

        public func multipartUpload(
            _ endpoint: Endpoint,
            method: BaseAPI.HTTPMethod,
            data: MultipartData
        ) async throws -> HTTPURLResponse {
            let startTime = Date()
            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

            do {
                var req = try await createBaseRequest(endpoint: endpoint, method: method)
                try req.addMultipartData(data: data)

                let (responseData, urlResponse) = try await session.data(for: req)

                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    throw APIError.invalidResponse(response: urlResponse)
                }

                logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")
                try runValidators(validators, response: httpResponse, data: responseData,
                                  request: req, endpoint: endpoint)
                return httpResponse

            } catch {
                let apiError = error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
                eventMonitor.requestDidFail(
                    URLRequest(url: endpoint.url), endpoint: endpoint.stringValue,
                    method: method.rawValue, error: apiError,
                    duration: Date().timeIntervalSince(startTime)
                )
                throw apiError
            }
        }

        public func multipartRequest(
            _ endpoint: Endpoint,
            method: BaseAPI.HTTPMethod,
            body: MultipartData,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) {
            Task {
                do {
                    callback(.success(try await multipartUpload(endpoint, method: method, data: body)))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - Raw Data Body

        public func post<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.post).body(raw: rawBody).response()
        }

        public func post<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await post(endpoint, rawBody: rawBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        public func put<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.put).body(raw: rawBody).response()
        }

        public func put<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await put(endpoint, rawBody: rawBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        public func patch<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data
        ) async throws -> APIResponse<Response> {
            try await request(endpoint).method(.patch).body(raw: rawBody).response()
        }

        public func patch<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await patch(endpoint, rawBody: rawBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
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
