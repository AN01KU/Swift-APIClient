import Foundation

extension BaseAPI {

    /// Generic HTTP API client with async/await and callback support
    open class BaseAPIClient<Endpoint: APIEndpoint>: @unchecked Sendable {

        // MARK: - HTTP Methods

        public enum HTTPMethod: String, CaseIterable {
            case get = "GET"
            case post = "POST"
            case put = "PUT"
            case patch = "PATCH"
            case delete = "DELETE"
        }

        // MARK: - Properties

        private let session: URLSession
        private let encoder: JSONEncoder
        private let decoder: JSONDecoder
        private let interceptorChain: InterceptorChain
        private let validators: [any ResponseValidator]
        private let analytics: APIAnalytics?
        private let logger: APIClientLoggingProtocol?
        private let unauthorizedHandler: (@Sendable (Endpoint) -> Void)?

        // MARK: - Initialization

        /// Create a client with an ordered list of interceptors and response validators.
        ///
        /// - Parameters:
        ///   - interceptors: Applied left-to-right on every outgoing request.
        ///   - validators: Run in order after each response is received; first failure throws.
        ///     Defaults to ``StatusCodeValidator`` (accepts 2xx only).
        public init(
            sessionConfiguration: URLSessionConfiguration = .default,
            encoder: JSONEncoder = JSONEncoder(),
            decoder: JSONDecoder = JSONDecoder(),
            interceptors: [any RequestInterceptor] = [],
            validators: [any ResponseValidator] = [StatusCodeValidator()],
            analytics: APIAnalytics? = nil,
            logger: APIClientLoggingProtocol? = nil,
            unauthorizedHandler: (@Sendable (Endpoint) -> Void)? = nil
        ) {
            self.session = URLSession(configuration: sessionConfiguration)
            self.encoder = encoder
            self.decoder = decoder
            self.interceptorChain = InterceptorChain(interceptors)
            self.validators = validators
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
            analytics: APIAnalytics? = nil,
            logger: APIClientLoggingProtocol? = nil,
            unauthorizedHandler: (@Sendable (Endpoint) -> Void)? = nil
        ) {
            self.init(
                sessionConfiguration: sessionConfiguration,
                encoder: encoder,
                decoder: decoder,
                interceptors: interceptor.map { [$0] } ?? [],
                validators: validators,
                analytics: analytics,
                logger: logger,
                unauthorizedHandler: unauthorizedHandler
            )
        }

        // MARK: - GET Requests

        public func get<Response: Decodable>(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            let body: EmptyResponse? = nil
            return try await performRequest(
                endpoint: endpoint,
                method: .get,
                body: body,
                printRequestBody: false,
                printResponseBody: printResponseBody
            )
        }

        public func get<Response>(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await get(
                        endpoint, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - POST Requests

        public func post<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false
        ) async throws -> HTTPURLResponse {
            let result: APIResponse<EmptyResponse> = try await performRequest(
                endpoint: endpoint,
                method: .post,
                body: body,
                printRequestBody: printRequestBody,
                printResponseBody: false
            )
            return result.response
        }

        public func post<Request>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    let result = try await post(
                        endpoint, body: body, printRequestBody: printRequestBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        public func post<Request: Encodable, Response: Decodable>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            try await performRequest(
                endpoint: endpoint,
                method: .post,
                body: body,
                printRequestBody: printRequestBody,
                printResponseBody: printResponseBody
            )
        }

        public func post<Request, Response>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable, Request: Encodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await post(
                        endpoint,
                        body: body,
                        printRequestBody: printRequestBody,
                        printResponseBody: printResponseBody
                    )
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - PUT Requests

        public func put<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false
        ) async throws -> HTTPURLResponse {
            let result: APIResponse<EmptyResponse> = try await performRequest(
                endpoint: endpoint,
                method: .put,
                body: body,
                printRequestBody: printRequestBody,
                printResponseBody: false
            )
            return result.response
        }

        public func put<Request>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    let result = try await put(
                        endpoint, body: body, printRequestBody: printRequestBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - PATCH Requests

        public func patch<Request: Encodable>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false
        ) async throws -> HTTPURLResponse {
            let result: APIResponse<EmptyResponse> = try await performRequest(
                endpoint: endpoint,
                method: .patch,
                body: body,
                printRequestBody: printRequestBody,
                printResponseBody: false
            )
            return result.response
        }

        public func patch<Request>(
            _ endpoint: Endpoint,
            body: Request,
            printRequestBody: Bool = false,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) where Request: Encodable & Sendable {
            Task {
                do {
                    let result = try await patch(
                        endpoint, body: body, printRequestBody: printRequestBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - DELETE Requests

        public func delete(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false
        ) async throws -> HTTPURLResponse {
            let body: EmptyResponse? = nil
            let result: APIResponse<EmptyResponse> = try await performRequest(
                endpoint: endpoint,
                method: .delete,
                body: body,
                printRequestBody: false,
                printResponseBody: printResponseBody
            )
            return result.response
        }

        public func delete(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) {
            Task {
                do {
                    let result = try await delete(
                        endpoint, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        public func delete<Response: Decodable>(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            let body: EmptyResponse? = nil
            return try await performRequest(
                endpoint: endpoint,
                method: .delete,
                body: body,
                printRequestBody: false,
                printResponseBody: printResponseBody
            )
        }

        public func delete<Response>(
            _ endpoint: Endpoint,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await delete(
                        endpoint, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - Multipart Upload

        public func multipartUpload(
            _ endpoint: Endpoint,
            method: HTTPMethod,
            data: MultipartData,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false
        ) async throws -> HTTPURLResponse {
            let startTime = Date()

            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

            do {
                var request = try await createBaseRequest(endpoint: endpoint, method: method)
                try request.addMultipartData(
                    data: data,
                    printRequestBody: printRequestBody,
                    logger: logger,
                    endpoint: endpoint.stringValue,
                    method: method.rawValue
                )

                let (data, urlResponse) = try await session.data(for: request)

                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    let error: APIError = .invalidResponse(response: urlResponse)
                    logger?.error(
                        "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Invalid response")"
                    )
                    logAnalytics(endpoint, method, startTime, false, nil, error.errorDescription)
                    throw error
                }

                logger?.info(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)"
                )
                try validateResponse(httpResponse, data: data, request: request, endpoint: endpoint)
                logAnalytics(endpoint, method, startTime, true, httpResponse.statusCode, nil)

                if printResponseBody {
                    if let decodedString = String(data: data, encoding: .utf8) {
                        logger?.info(
                            "\(method.rawValue):\(endpoint.stringValue) REQUEST | responseData string: \(decodedString)"
                        )
                    }
                }
                return httpResponse

            } catch {
                let apiError =
                    error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)"
                )
                logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                throw apiError
            }
        }

        public func multipartRequest(
            _ endpoint: Endpoint,
            method: HTTPMethod,
            body: MultipartData,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIURLResult) -> Void
        ) {
            let method = method
            Task {
                do {
                    let result = try await multipartUpload(
                        endpoint,
                        method: method,
                        data: body,
                        printRequestBody: printRequestBody,
                        printResponseBody: printResponseBody
                    )
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: - Raw Data Body Requests

        /// POST with a pre-serialized `Data` body and a decoded response.
        ///
        /// Use this when replaying queued changes whose body was already JSON-encoded
        /// (e.g. from a change queue store) to avoid double-encoding.
        public func post<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            try await performRawBodyRequest(
                endpoint: endpoint, method: .post, rawBody: rawBody,
                printResponseBody: printResponseBody)
        }

        public func post<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await post(
                        endpoint, rawBody: rawBody, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        /// PUT with a pre-serialized `Data` body and a decoded response.
        public func put<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            try await performRawBodyRequest(
                endpoint: endpoint, method: .put, rawBody: rawBody,
                printResponseBody: printResponseBody)
        }

        public func put<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await put(
                        endpoint, rawBody: rawBody, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        /// PATCH with a pre-serialized `Data` body and a decoded response.
        public func patch<Response: Decodable>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            try await performRawBodyRequest(
                endpoint: endpoint, method: .patch, rawBody: rawBody,
                printResponseBody: printResponseBody)
        }

        public func patch<Response>(
            _ endpoint: Endpoint,
            rawBody: Data,
            printResponseBody: Bool = false,
            then callback: @escaping @Sendable (APIResult<Response>) -> Void
        ) where Response: Decodable & Sendable {
            Task {
                do {
                    let result: APIResponse<Response> = try await patch(
                        endpoint, rawBody: rawBody, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    callback(.failure(error as? APIError ?? .unknown))
                }
            }
        }

        // MARK: - Public Helper Functions

        public func performRequest<Request: Encodable>(
            endpoint: Endpoint,
            method: HTTPMethod,
            body: Request?,
            printRequestBody: Bool = false
        ) async throws -> (data: Data, urlResponse: URLResponse) {
            let startTime = Date()

            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

            do {
                var request = try await createBaseRequest(endpoint: endpoint, method: method)
                try request.addJSONBody(
                    body,
                    encoder: encoder,
                    printRequestBody: printRequestBody,
                    logger: logger,
                    endpoint: endpoint.stringValue,
                    method: method.rawValue
                )

                let result = try await session.data(for: request)

                if let httpResponse = result.1 as? HTTPURLResponse {
                    logger?.info(
                        "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)"
                    )
                }

                return result
            } catch {
                let apiError =
                    error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)"
                )
                logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                throw apiError
            }
        }

        // MARK: - Private Implementation

        private func performRequest<Request: Encodable, Response: Decodable>(
            endpoint: Endpoint,
            method: HTTPMethod,
            body: Request?,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            let startTime = Date()
            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

            var attemptCount = 0
            while true {
                attemptCount += 1
                do {
                    var request = try await createBaseRequest(endpoint: endpoint, method: method)
                    try request.addJSONBody(
                        body,
                        encoder: encoder,
                        printRequestBody: printRequestBody,
                        logger: logger,
                        endpoint: endpoint.stringValue,
                        method: method.rawValue
                    )

                    let (data, urlResponse) = try await session.data(for: request)

                    return try handleResponse(
                        endpoint: endpoint,
                        method: method,
                        request: request,
                        data: data,
                        urlResponse: urlResponse,
                        startTime: startTime,
                        printResponseBody: printResponseBody
                    )
                } catch {
                    let apiError = error as? APIError ?? APIError.networkError(error.localizedDescription)
                    let decision = await interceptorChain.retry(
                        URLRequest(url: endpoint.url),
                        dueTo: apiError,
                        attemptCount: attemptCount
                    )
                    switch decision {
                    case .retry(let delay):
                        logger?.info(
                            "\(method.rawValue):\(endpoint.stringValue) REQUEST | retrying (attempt \(attemptCount)) after \(delay)s"
                        )
                        if delay > 0 {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    case .doNotRetry:
                        logger?.error(
                            "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)"
                        )
                        logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                        throw apiError
                    }
                }
            }
        }

        private func handleResponse<Response: Decodable>(
            endpoint: Endpoint,
            method: HTTPMethod,
            request: URLRequest,
            data: Data,
            urlResponse: URLResponse,
            startTime: Date,
            printResponseBody: Bool = false
        ) throws -> APIResponse<Response> {
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                let error: APIError = .invalidResponse(response: urlResponse)
                logger?.error(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Invalid response")"
                )
                logAnalytics(endpoint, method, startTime, false, nil, error.errorDescription)
                throw error
            }

            logger?.info(
                "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)"
            )

            try validateResponse(httpResponse, data: data, request: request, endpoint: endpoint)

            let decodedResponse: Response
            do {
                decodedResponse = try data.decode(
                    Response.self,
                    decoder: decoder,
                    printResponseBody: printResponseBody,
                    logger: logger,
                    endpoint: endpoint.stringValue,
                    method: method.rawValue
                )
            } catch {
                let apiError = BaseAPI.APIError.decodingFailed(
                    response: httpResponse,
                    error: error.localizedDescription
                )
                logger?.error(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.errorDescription ?? "Decoding failed")"
                )
                logAnalytics(
                    endpoint, method, startTime, false, httpResponse.statusCode,
                    apiError.errorDescription)
                throw apiError
            }

            logAnalytics(endpoint, method, startTime, true, httpResponse.statusCode, nil)
            return (decodedResponse, httpResponse)
        }

        private func performRawBodyRequest<Response: Decodable>(
            endpoint: Endpoint,
            method: HTTPMethod,
            rawBody: Data,
            printResponseBody: Bool = false
        ) async throws -> APIResponse<Response> {
            let startTime = Date()
            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

            var attemptCount = 0
            while true {
                attemptCount += 1
                do {
                    var request = try await createBaseRequest(endpoint: endpoint, method: method)
                    request.httpBody = rawBody

                    let (data, urlResponse) = try await session.data(for: request)

                    return try handleResponse(
                        endpoint: endpoint,
                        method: method,
                        request: request,
                        data: data,
                        urlResponse: urlResponse,
                        startTime: startTime,
                        printResponseBody: printResponseBody
                    )
                } catch {
                    let apiError = error as? APIError ?? APIError.networkError(error.localizedDescription)
                    let decision = await interceptorChain.retry(
                        URLRequest(url: endpoint.url),
                        dueTo: apiError,
                        attemptCount: attemptCount
                    )
                    switch decision {
                    case .retry(let delay):
                        logger?.info(
                            "\(method.rawValue):\(endpoint.stringValue) REQUEST | retrying (attempt \(attemptCount)) after \(delay)s"
                        )
                        if delay > 0 {
                            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        }
                    case .doNotRetry:
                        logger?.error(
                            "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)"
                        )
                        logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                        throw apiError
                    }
                }
            }
        }

        private func createBaseRequest(
            endpoint: Endpoint,
            method: HTTPMethod
        ) async throws -> URLRequest {
            var request = URLRequest(url: endpoint.url)
            request.httpMethod = method.rawValue
            request.addJSONHeaders(additionalHeaders: endpoint.headers ?? [:])
            request = try await interceptorChain.adapt(request)
            return request
        }

        private func validateResponse(
            _ response: HTTPURLResponse,
            data: Data,
            request: URLRequest,
            endpoint: Endpoint
        ) throws {
            // Fire the 401 side-effect before validators so the handler always runs on unauthorized.
            if response.statusCode == 401 {
                logger?.error("unauthorized/incorrect auth token")
                unauthorizedHandler?(endpoint)
            }

            for validator in validators {
                do {
                    try validator.validate(response, data: data, for: request)
                } catch {
                    let apiError = error as? APIError ?? APIError.serverError(
                        response: response,
                        code: response.statusCode,
                        requestID: response.value(forHTTPHeaderField: "x-request-id") ?? "N/A"
                    )
                    logger?.error(
                        "\(endpoint.stringValue) REQUEST | error: \(apiError.errorDescription ?? "Validation failed")"
                    )
                    throw apiError
                }
            }
        }

        private func logAnalytics(
            _ endpoint: Endpoint,
            _ method: HTTPMethod,
            _ startTime: Date,
            _ success: Bool,
            _ statusCode: Int?,
            _ error: String?
        ) {
            analytics?.addAnalytics(
                endpoint: endpoint.stringValue,
                method: method.rawValue,
                startTime: startTime,
                endTime: Date(),
                success: success,
                statusCode: statusCode,
                error: error
            )
        }
    }
}
