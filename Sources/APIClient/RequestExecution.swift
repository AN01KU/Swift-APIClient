import Foundation

extension BaseAPI.BaseAPIClient {

    // MARK: - Builder Execution

    func execute<Response: Decodable & Sendable>(
        _ builder: BaseAPI.RequestBuilder<Endpoint>
    ) async throws -> BaseAPI.APIResponse<Response> {
        let endpoint = builder.endpoint
        let method = builder.httpMethod
        let startTime = Date()
        let validators = builder.overrideValidators ?? self.validators

        logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

        var attemptCount = 0
        var firstRequest: URLRequest?
        while true {
            attemptCount += 1
            do {
                var request = try await createBaseRequest(endpoint: endpoint, method: method)
                try applyBuilderOverrides(builder, to: &request)

                if attemptCount == 1 {
                    firstRequest = request
                    eventMonitor.requestDidStart(request, endpoint: endpoint.stringValue, method: method.rawValue)
                }

                let (data, urlResponse) = try await session.data(for: request)

                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    throw BaseAPI.APIError.invalidResponse(response: urlResponse)
                }

                logger?.info(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")

                try runValidators(
                    validators, response: httpResponse, data: data,
                    request: request, endpoint: endpoint)

                let decoded: Response
                do {
                    decoded = try data.decode(
                        Response.self, decoder: decoder,
                        endpoint: endpoint.stringValue, method: method.rawValue)
                } catch {
                    let apiError = BaseAPI.APIError.decodingFailed(
                        response: httpResponse, error: error.localizedDescription)
                    logger?.error(
                        "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.errorDescription ?? "")"
                    )
                    eventMonitor.requestDidFail(
                        request, endpoint: endpoint.stringValue,
                        method: method.rawValue, error: apiError,
                        duration: Date().timeIntervalSince(startTime))
                    throw apiError
                }

                eventMonitor.requestDidFinish(
                    request, endpoint: endpoint.stringValue,
                    method: method.rawValue, response: httpResponse,
                    duration: Date().timeIntervalSince(startTime))
                return (decoded, httpResponse)

            } catch {
                guard
                    let apiError = try await handleRetry(
                        error, endpoint: endpoint, method: method,
                        attemptCount: attemptCount, firstRequest: firstRequest, startTime: startTime
                    )
                else { continue }
                throw apiError
            }
        }
    }

    func executeRaw(_ builder: BaseAPI.RequestBuilder<Endpoint>) async throws -> BaseAPI.APIResponse<Data> {
        let endpoint = builder.endpoint
        let method = builder.httpMethod
        let startTime = Date()
        let validators = builder.overrideValidators ?? self.validators

        logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

        var attemptCount = 0
        var firstRequest: URLRequest?
        while true {
            attemptCount += 1
            do {
                var request = try await createBaseRequest(endpoint: endpoint, method: method)
                try applyBuilderOverrides(builder, to: &request)

                if attemptCount == 1 {
                    firstRequest = request
                    eventMonitor.requestDidStart(request, endpoint: endpoint.stringValue, method: method.rawValue)
                }

                let (data, urlResponse) = try await session.data(for: request)

                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    throw BaseAPI.APIError.invalidResponse(response: urlResponse)
                }

                logger?.info(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")

                try runValidators(
                    validators, response: httpResponse, data: data,
                    request: request, endpoint: endpoint)

                eventMonitor.requestDidFinish(
                    request, endpoint: endpoint.stringValue,
                    method: method.rawValue, response: httpResponse,
                    duration: Date().timeIntervalSince(startTime))
                return (data, httpResponse)

            } catch {
                guard
                    let apiError = try await handleRetry(
                        error, endpoint: endpoint, method: method,
                        attemptCount: attemptCount, firstRequest: firstRequest, startTime: startTime
                    )
                else { continue }
                throw apiError
            }
        }
    }

    func executeDownload(
        _ builder: BaseAPI.RequestBuilder<Endpoint>
    ) -> AsyncThrowingStream<BaseAPI.DownloadProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let endpoint = builder.endpoint
                let method = builder.httpMethod
                let validators = builder.overrideValidators ?? self.validators

                do {
                    var request = try await createBaseRequest(endpoint: endpoint, method: method)
                    try applyBuilderOverrides(builder, to: &request)

                    eventMonitor.requestDidStart(request, endpoint: endpoint.stringValue, method: method.rawValue)

                    let startTime = Date()
                    let (asyncBytes, urlResponse) = try await session.bytes(for: request)

                    guard let httpResponse = urlResponse as? HTTPURLResponse else {
                        throw BaseAPI.APIError.invalidResponse(response: urlResponse)
                    }

                    try runValidators(
                        validators, response: httpResponse, data: Data(),
                        request: request, endpoint: endpoint)

                    let totalBytes = httpResponse.value(forHTTPHeaderField: "Content-Length")
                        .flatMap { Int64($0) }

                    var accumulated = Data()
                    for try await byte in asyncBytes {
                        accumulated.append(byte)
                        continuation.yield(
                            BaseAPI.DownloadProgress(
                                bytesReceived: Int64(accumulated.count),
                                totalBytesExpected: totalBytes,
                                data: nil,
                                response: httpResponse
                            ))
                    }

                    continuation.yield(
                        BaseAPI.DownloadProgress(
                            bytesReceived: Int64(accumulated.count),
                            totalBytesExpected: totalBytes,
                            data: accumulated,
                            response: httpResponse
                        ))
                    eventMonitor.requestDidFinish(
                        request, endpoint: endpoint.stringValue,
                        method: method.rawValue, response: httpResponse,
                        duration: Date().timeIntervalSince(startTime))
                    continuation.finish()

                } catch {
                    let apiError =
                        error as? BaseAPI.APIError ?? BaseAPI.APIError.networkError(error as? URLError ?? URLError(.unknown))
                    eventMonitor.requestDidFail(
                        URLRequest(url: builder.endpoint.url),
                        endpoint: builder.endpoint.stringValue,
                        method: builder.httpMethod.rawValue,
                        error: apiError,
                        duration: 0
                    )
                    continuation.finish(throwing: apiError)
                }
            }
        }
    }

    // MARK: - Public Raw Execution Helper

    /// Execute a request and return the raw `(Data, URLResponse)` tuple.
    ///
    /// - Warning: This method bypasses the client's validators, event monitors, and retry
    ///   logic. Prefer `request(_:).responseData()` for consistent behaviour.
    public func performRequest<Request: Encodable>(
        endpoint: Endpoint,
        method: BaseAPI.HTTPMethod,
        body: Request?
    ) async throws -> (data: Data, urlResponse: URLResponse) {
        logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | started")

        do {
            var request = try await createBaseRequest(endpoint: endpoint, method: method)
            try request.addJSONBody(body, encoder: encoder)

            let result = try await session.data(for: request)

            if let httpResponse = result.1 as? HTTPURLResponse {
                logger?.info(
                    "\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")
            }
            return result

        } catch {
            let apiError = error as? BaseAPI.APIError ?? BaseAPI.APIError.networkError(error as? URLError ?? URLError(.unknown))
            logger?.error(
                "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
            throw apiError
        }
    }

    // MARK: - Internal Helpers

    func createBaseRequest(endpoint: Endpoint, method: BaseAPI.HTTPMethod) async throws -> URLRequest {
        var request = URLRequest(url: endpoint.url)
        request.httpMethod = method.rawValue
        request.addJSONHeaders(additionalHeaders: endpoint.headers ?? [:])
        return try await interceptorChain.adapt(request)
    }

    func runValidators(
        _ validators: [any BaseAPI.ResponseValidator],
        response: HTTPURLResponse,
        data: Data,
        request: URLRequest,
        endpoint: Endpoint
    ) throws {
        for validator in validators {
            do {
                try validator.validate(response, data: data, for: request)
            } catch {
                let apiError =
                    error as? BaseAPI.APIError
                    ?? BaseAPI.APIError.serverError(
                        response: response,
                        code: response.statusCode,
                        requestID: response.value(forHTTPHeaderField: "x-request-id") ?? "N/A"
                    )
                logger?.error(
                    "\(endpoint.stringValue) REQUEST | error: \(apiError.errorDescription ?? "Validation failed")")
                throw apiError
            }
        }
    }

    // MARK: - Private Helpers

    private func applyBuilderOverrides(_ builder: BaseAPI.RequestBuilder<Endpoint>, to request: inout URLRequest) throws
    {
        if let timeout = builder.timeoutInterval { request.timeoutInterval = timeout }
        if let policy = builder.cachePolicy { request.cachePolicy = policy }
        for (key, value) in builder.additionalHeaders { request.setValue(value, forHTTPHeaderField: key) }

        switch builder.body {
        case .json(let value):
            do {
                request.httpBody = try encoder.encode(AnyEncodable(value))
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            } catch {
                throw BaseAPI.APIError.encodingFailed
            }
        case .formURL(let fields):
            request.httpBody = fields.formURLEncoded()
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        case .raw(let data, let contentType):
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        case .none:
            break
        }
    }

    /// Returns the `APIError` to throw, or `nil` if the request should be retried.
    private func handleRetry(
        _ error: Error,
        endpoint: Endpoint,
        method: BaseAPI.HTTPMethod,
        attemptCount: Int,
        firstRequest: URLRequest?,
        startTime: Date
    ) async throws -> BaseAPI.APIError? {
        let apiError = error as? BaseAPI.APIError ?? BaseAPI.APIError.networkError(error as? URLError ?? URLError(.unknown))
        let decision = await interceptorChain.retry(
            URLRequest(url: endpoint.url),
            dueTo: apiError, attemptCount: attemptCount)
        switch decision {
        case .retry(let delay):
            logger?.info(
                "\(method.rawValue):\(endpoint.stringValue) REQUEST | retrying (attempt \(attemptCount)) after \(delay)s"
            )
            let req = firstRequest ?? URLRequest(url: endpoint.url)
            eventMonitor.requestWillRetry(
                req, endpoint: endpoint.stringValue,
                method: method.rawValue,
                attemptCount: attemptCount, delay: delay)
            if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            return nil
        case .doNotRetry:
            logger?.error(
                "\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
            if case .serverError(let response, _, _) = apiError, response.statusCode == 401 {
                logger?.error("unauthorized/incorrect auth token")
                unauthorizedHandler?(endpoint)
            }
            let req = firstRequest ?? URLRequest(url: endpoint.url)
            eventMonitor.requestDidFail(
                req, endpoint: endpoint.stringValue,
                method: method.rawValue, error: apiError,
                duration: Date().timeIntervalSince(startTime))
            return apiError
        }
    }
}
