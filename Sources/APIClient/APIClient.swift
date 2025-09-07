import Foundation

extension BaseAPI {

    /// Generic HTTP API client with async/await and callback support
    open class BaseAPIClient<Endpoint: APIEndpoint> {

        // MARK: - HTTP Methods

        public enum HTTPMethod: String, CaseIterable {
            case get = "GET"
            case post = "POST"
            case put = "PUT"
            case delete = "DELETE"
        }

        // MARK: - Properties

        private let session: URLSession
        private let encoder: JSONEncoder
        private let decoder: JSONDecoder
        private let analytics: APIAnalytics?
        private let logger: APIClientLoggingProtocol?
        private let unauthorizedHandler: ((Endpoint) -> Void)?

        // MARK: - Initialization

        public init(
            sessionConfiguration: URLSessionConfiguration = .default,
            encoder: JSONEncoder = JSONEncoder(),
            decoder: JSONDecoder = JSONDecoder(),
            analytics: APIAnalytics? = nil,
            logger: APIClientLoggingProtocol? = nil,
            unauthorizedHandler: ((Endpoint) -> Void)? = nil
        ) {
            self.session = URLSession(configuration: sessionConfiguration)
            self.encoder = encoder
            self.decoder = decoder
            self.analytics = analytics
            self.logger = logger
            self.unauthorizedHandler = unauthorizedHandler
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
            then callback: @escaping (APIResult<Response>) -> Void
        ) where Response: Decodable {
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
            then callback: @escaping (APIURLResult) -> Void
        ) where Request: Encodable {
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
            return try await performRequest(
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
            then callback: @escaping (APIResult<Response>) -> Void
        ) where Response: Decodable, Request: Encodable {
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
            then callback: @escaping (APIURLResult) -> Void
        ) where Request: Encodable {
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
                var request = try createBaseRequest(endpoint: endpoint, method: method)
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
                try validateResponse(httpResponse, endpoint: endpoint)
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
            then callback: @escaping (APIURLResult) -> Void
        ) {
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
                var request = try createBaseRequest(endpoint: endpoint, method: method)
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

            do {
                var request = try createBaseRequest(endpoint: endpoint, method: method)
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
                    data: data,
                    urlResponse: urlResponse,
                    startTime: startTime,
                    printResponseBody: printResponseBody
                )
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

        private func handleResponse<Response: Decodable>(
            endpoint: Endpoint,
            method: HTTPMethod,
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

            try validateResponse(httpResponse, endpoint: endpoint)

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

        private func createBaseRequest(endpoint: Endpoint, method: HTTPMethod) throws -> URLRequest
        {
            guard let authHeader = endpoint.authHeader else {
                throw APIError.missingAuthHeader
            }

            var request = URLRequest(url: endpoint.url)
            request.httpMethod = method.rawValue
            request.addJSONHeaders(authHeader: authHeader)

            return request
        }

        private func validateResponse(_ response: HTTPURLResponse, endpoint: Endpoint) throws {
            let statusCode = response.statusCode
            guard (200...299).contains(statusCode) else {
                if statusCode == 401 {
                    logger?.error("unauthorized/incorrect auth token")
                    unauthorizedHandler?(endpoint)
                }
                let requestId = response.value(forHTTPHeaderField: "x-request-id") ?? "N/A"
                let error = APIError.serverError(
                    response: response,
                    code: statusCode,
                    requestID: requestId
                )
                logger?.error(
                    "\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Server error")"
                )
                throw error
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
