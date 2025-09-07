//
//  BaseAPIClient.swift
//  Scalefusion-Service
//
//  Created by Ankush Ganesh on 28/08/25.
//

import Foundation

open class BaseAPI {
    public typealias APIURLResult = Result<HTTPURLResponse, APIError>
    public typealias APIResult<T> = Result<APIResponse<T>, APIError>
    public typealias APIResponse<T> = (data: T, response: HTTPURLResponse)
    
    public init() { }

    public struct MultipartData {
        public let parameters: [String: AnyObject]?
        public let fileKeyName: String
        public let fileURLs: [URL]?

        public init(
            parameters: [String: AnyObject]? = nil, fileKeyName: String, fileURLs: [URL]? = nil
        ) {
            self.parameters = parameters
            self.fileKeyName = fileKeyName
            self.fileURLs = fileURLs
        }
        
        public var stringValue: String {
            var components: [String] = []
            
            if let parameters = parameters, !parameters.isEmpty {
                let paramStrings = parameters.map { "\($0.key): \($0.value)" }
                components.append("parameters: [\(paramStrings.joined(separator: ", "))]")
            }
            
            components.append("fileKeyName: \(fileKeyName)")
            
            if let fileURLs = fileURLs, !fileURLs.isEmpty {
                let fileNames = fileURLs.map { $0.lastPathComponent }
                components.append("files: [\(fileNames.joined(separator: ", "))]")
            }
            
            return components.joined(separator: ", ")
        }
    }

    // MARK: - Protocols

    public protocol APIEndpoint: Equatable {
        var url: URL { get }
        var stringValue: String { get }
        var authHeader: [String: String]? { get }
    }

    public protocol APIClientLoggingProtocol {
        func info(_ value: String)
        func debug(_ value: String)
        func error(_ value: String)
        func warn(_ value: String)
    }

    public protocol APIAnalytics {
        func addAnalytics(
            endpoint: String,
            method: String,
            startTime: Date,
            endTime: Date,
            success: Bool,
            statusCode: Int?,
            error: String?
        )
    }

    public enum APIError: Error, LocalizedError {
        case missingAuthHeader
        case encodingFailed
        case networkError(String)
        case invalidResponse(response: URLResponse)
        case serverError(response: HTTPURLResponse, code: Int, requestID: String)
        case decodingFailed(response: HTTPURLResponse, error: String)
        case unknown

        public var errorDescription: String? {
            switch self {
            case .missingAuthHeader:
                return "Authentication header is missing"
            case .encodingFailed:
                return "Failed to encode request body"
            case .networkError(let message):
                return "Network error: \(message)"
            case .invalidResponse(_):
                return "Invalid response received"
            case .serverError(_, let code, let requestID):
                return "Server error \(code), Request ID: \(requestID)"
            case .decodingFailed(_, let message):
                return "Failed to decode response: \(message)"
            case .unknown:
                return "Unknown error occurred"
            }
        }

        public var isClientError: Bool {
            switch self {
            case .missingAuthHeader, .encodingFailed, .decodingFailed:
                return true
            default:
                return false
            }
        }
    }

    public struct EmptyResponse: Codable {
        public init() {}
    }

    // MARK: - Base API Client
    open class BaseAPIClient<Endpoint: APIEndpoint> {

        // MARK: - Types

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
            logger: APIClientLoggingProtocol?,
            unauthorizedHandler: ((Endpoint) -> Void)? = nil
        ) {
            self.session = URLSession(configuration: sessionConfiguration)
            self.encoder = encoder
            self.decoder = decoder
            self.analytics = analytics
            self.logger = logger
            self.unauthorizedHandler = unauthorizedHandler
        }

        // MARK: - Public API

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
                    let result: APIResponse<Response> = try await get(endpoint, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

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
                    let result = try await post(endpoint, body: body, printRequestBody: printRequestBody)
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
            skipAuthHeader: Bool = false,
            printRequestBody: Bool = false,
            printResponseBody: Bool = false,
            then callback: @escaping (APIResult<Response>) -> Void
        ) where Response: Decodable, Request: Encodable {
            Task {
                do {
                    let result: APIResponse<Response> = try await post(endpoint, body: body, printRequestBody: printRequestBody, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

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
                    let result = try await put(endpoint, body: body, printRequestBody: printRequestBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

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
                try request.addMultipartData(data: data, printRequestBody: printRequestBody, logger: logger, endpoint: endpoint.stringValue, method: method.rawValue)

                let (data, urlResponse) = try await session.data(for: request)

                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    let error: APIError = .invalidResponse(response: urlResponse)
                    logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Invalid response")")
                    logAnalytics(endpoint, method, startTime, false, nil, error.errorDescription)
                    throw error
                }

                logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")
                try validateResponse(httpResponse, endpoint: endpoint)
                logAnalytics(endpoint, method, startTime, true, httpResponse.statusCode, nil)
                if printResponseBody {
                    if let decodedString = String(data: data, encoding: .utf8) {
                        logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | responseData string: \(decodedString)")
                    }
                }
                return httpResponse

            } catch {
                let apiError =
                    error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
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
                    let result = try await multipartUpload(endpoint, method: method, data: body, printRequestBody: printRequestBody, printResponseBody: printResponseBody)
                    callback(.success(result))
                } catch {
                    let error: APIError = error as? APIError ?? .unknown
                    callback(.failure(error))
                }
            }
        }

        // MARK: Public Helper funciton
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
                try request.addJSONBody(body, encoder: encoder, printRequestBody: printRequestBody, logger: logger, endpoint: endpoint.stringValue, method: method.rawValue)

                let result = try await session.data(for: request)
                
                if let httpResponse = result.1 as? HTTPURLResponse {
                    logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")
                }
                
                return result
            } catch {
                let apiError =
                    error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
                logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                throw apiError
            }
        }

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
                try request.addJSONBody(body, encoder: encoder, printRequestBody: printRequestBody, logger: logger, endpoint: endpoint.stringValue, method: method.rawValue)

                let (data, urlResponse) = try await session.data(for: request)

                return try handleResponse(
                    endpoint: endpoint, method: method, data: data, urlResponse: urlResponse,
                    startTime: startTime, printResponseBody: printResponseBody)
            } catch {
                let apiError =
                    error as? APIError ?? APIError.networkError(error.localizedDescription)
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.localizedDescription)")
                logAnalytics(endpoint, method, startTime, false, nil, apiError.localizedDescription)
                throw apiError
            }
        }

        // MARK: - Private Implementation

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
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Invalid response")")
                logAnalytics(endpoint, method, startTime, false, nil, error.errorDescription)
                throw error
            }

            logger?.info("\(method.rawValue):\(endpoint.stringValue) REQUEST | Response code: \(httpResponse.statusCode)")

            try validateResponse(httpResponse, endpoint: endpoint)

            let decodedResponse: Response
            do {
                decodedResponse = try data.decode(Response.self, decoder: decoder, printResponseBody: printResponseBody, logger: logger, endpoint: endpoint.stringValue, method: method.rawValue)
            } catch {
                let apiError = BaseAPI.APIError.decodingFailed(
                    response: httpResponse, error: error.localizedDescription)
                logger?.error("\(method.rawValue):\(endpoint.stringValue) REQUEST | error: \(apiError.errorDescription ?? "Decoding failed")")
                logAnalytics(endpoint, method, startTime, false, httpResponse.statusCode, apiError.errorDescription)
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
                    response: response, code: statusCode, requestID: requestId)
                logger?.error("\(endpoint.stringValue) REQUEST | error: \(error.errorDescription ?? "Server error")")
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

// MARK: - URLRequest Extensions

extension URLRequest {

    mutating func addJSONHeaders(authHeader: [String: String]) {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        headers.merge(authHeader) { _, new in new }

        for (key, value) in headers {
            setValue(value, forHTTPHeaderField: key)
        }
    }

    mutating func addJSONBody<T: Encodable>(_ body: T?, encoder: JSONEncoder, printRequestBody: Bool = false, logger: BaseAPI.APIClientLoggingProtocol?, endpoint: String, method: String) throws {
        guard let body = body else { return }

        do {
            let payload = try encoder.encode(body)
            httpBody = payload
            
            if printRequestBody {
                if let decodedString = String(data: payload, encoding: .utf8) {
                    logger?.info("\(method):\(endpoint) REQUEST | body string: \(decodedString)")
                }
            }
        } catch {
            throw BaseAPI.APIError.encodingFailed
        }
    }

    mutating func addMultipartData(data: BaseAPI.MultipartData, printRequestBody: Bool = false, logger: BaseAPI.APIClientLoggingProtocol?, endpoint: String, method: String) throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        timeoutInterval = 60
        cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            httpBody = try createMultipartBody(data: data, boundary: boundary)
            if printRequestBody {
                let stringValue = data.stringValue
                logger?.info("\(method):\(endpoint) REQUEST | body string: \(stringValue)")
            }
        } catch {
            throw BaseAPI.APIError.encodingFailed
        }
    }

    private func createMultipartBody(
        data: BaseAPI.MultipartData,
        boundary: String
    ) throws -> Data {
        var body = Data()

        // Add parameters
        if let parameters = data.parameters {
            for (key, value) in parameters {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
        }

        // Add files
        if let fileURLs = data.fileURLs {
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                let fileData = try Data(contentsOf: fileURL)
                let mimeType = URLSession.mimeTypeForPath(fileURL.pathExtension)

                body.appendString("--\(boundary)\r\n")
                body.appendString(
                    "Content-Disposition: form-data; name=\"\(data.fileKeyName)\"; filename=\"\(filename)\"\r\n"
                )
                body.appendString("Content-Type: \(mimeType)\r\n\r\n")
                body.append(fileData)
                body.appendString("\r\n")
            }
        }

        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

// MARK: - Data Extensions

extension Data {

    mutating func appendString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }

    func decode<T: Decodable>(_ type: T.Type, decoder: JSONDecoder, printResponseBody: Bool = false, logger: BaseAPI.APIClientLoggingProtocol? = nil, endpoint: String = "", method: String = "") throws -> T {
        // Handle empty response
        if isEmpty {
            if T.self == BaseAPI.EmptyResponse.self {
                return BaseAPI.EmptyResponse() as! T
            }
        }

        if printResponseBody {
            if let decodedString = String(data: self, encoding: .utf8) {
                logger?.info("\(method):\(endpoint) REQUEST | responseData string: \(decodedString)")
            }
        }

        return try decoder.decode(type, from: self)
    }
}

// MARK: - URLSession Extensions

extension URLSession {
    class func mimeTypeForPath(_ path: String) -> String {
        let url = NSURL(fileURLWithPath: path)
        let pathExtension = url.pathExtension
        
        if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension! as NSString, nil)?.takeRetainedValue() {
            if let mimetype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassMIMEType)?.takeRetainedValue() {
                return mimetype as String
            }
        }
        return "application/octet-stream"
    }
}

// MARK: APIError Extensions

extension BaseAPI.APIError {
    public func getResponse() -> HTTPURLResponse? {
        switch self {
        case .serverError(let response, _, _, ):
            return response
        case .decodingFailed(let response, _):
            return response
        default:
            return nil
        }
    }
}
