import Foundation
import Testing
import UniformTypeIdentifiers

@testable import APIClient

@Suite("API Client Tests")
struct APIClientTests {

    // MARK: - Base API Tests

    @Test("BaseAPI type existence")
    func baseAPITypeExistence() throws {
        #expect(type(of: BaseAPI.self) == BaseAPI.Type.self)
        let emptyResponse = BaseAPI.EmptyResponse()
        #expect(type(of: emptyResponse) == BaseAPI.EmptyResponse.self)
    }

    @Test("BaseAPIClient initialization")
    func baseAPIClientInitialization() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(logger: nil)
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("BaseAPIClient initialization with dependencies")
    func baseAPIClientInitializationWithDependencies() throws {
        let logger = MockLogger()
        let analytics = MockAnalytics()
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(analytics: analytics, logger: logger)
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    // MARK: - Error Handling Tests

    @Test("APIError descriptions")
    func apiErrorDescriptions() throws {
        let errors: [BaseAPI.APIError] = [.encodingFailed, .networkError("Test"), .unknown]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("APIError client error classification")
    func apiErrorClientErrorClassification() throws {
        #expect(BaseAPI.APIError.encodingFailed.isClientError == true)
        #expect(BaseAPI.APIError.decodingFailed(response: HTTPURLResponse(), error: "test").isClientError == true)
        #expect(BaseAPI.APIError.networkError("test").isClientError == false)
        #expect(BaseAPI.APIError.unknown.isClientError == false)
    }

    @Test("APIError getResponse functionality")
    func apiErrorGetResponse() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!

        #expect(
            BaseAPI.APIError.serverError(response: httpResponse, code: 500, requestID: "123").getResponse()
                == httpResponse)
        #expect(BaseAPI.APIError.decodingFailed(response: httpResponse, error: "err").getResponse() == httpResponse)
        #expect(BaseAPI.APIError.networkError("fail").getResponse() == nil)
    }

    @Test("APIError localized descriptions")
    func apiErrorLocalizedDescriptions() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 400,
            httpVersion: nil, headerFields: nil)!

        let errors: [BaseAPI.APIError] = [
            .encodingFailed, .networkError("timeout"),
            .invalidResponse(response: URLResponse()),
            .serverError(response: httpResponse, code: 400, requestID: "req-123"),
            .decodingFailed(response: httpResponse, error: "Invalid JSON"),
            .unknown,
        ]
        for error in errors {
            #expect(!error.localizedDescription.isEmpty)
            #expect(error.localizedDescription.count > 5)
        }
    }

    @Test("API error response handling")
    func apiErrorResponseHandling() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/test")!, statusCode: 404,
            httpVersion: nil, headerFields: ["x-request-id": "req-123"])!

        let serverError = BaseAPI.APIError.serverError(response: httpResponse, code: 404, requestID: "req-123")
        #expect(serverError.errorDescription?.contains("404") == true)
        #expect(serverError.errorDescription?.contains("req-123") == true)
        #expect(serverError.isClientError == false)
        #expect(serverError.getResponse() == httpResponse)
    }

    // MARK: - Endpoint Tests

    @Test("MockEndpoint functionality")
    func mockEndpointFunctionality() throws {
        let endpoint = MockEndpoint(endpoint: "users", token: "test-token")
        #expect(endpoint.url.absoluteString == "https://api.example.com/users")
        #expect(endpoint.stringValue == "users")
        #expect(endpoint.headers?["Authorization"] == "Bearer test-token")
        #expect(MockEndpoint(endpoint: "public", token: nil).headers?.isEmpty == true)
    }

    @Test("Endpoint URL construction")
    func endpointURLConstruction() throws {
        let endpoint = MockEndpoint(endpoint: "users/123", token: "test-token")
        #expect(endpoint.url.absoluteString == "https://api.example.com/users/123")
        #expect(endpoint.stringValue == "users/123")
        #expect(endpoint.headers?["Authorization"] == "Bearer test-token")
    }

    @Test("Endpoint without authentication")
    func endpointWithoutAuth() throws {
        let endpoint = MockEndpoint(endpoint: "public/data", token: nil)
        #expect(endpoint.url.absoluteString == "https://api.example.com/public/data")
        #expect(endpoint.headers?.isEmpty == true)
    }

    @Test("MockEndpoint edge cases")
    func mockEndpointEdgeCases() throws {
        #expect(MockEndpoint(endpoint: "secure", token: "abc123").headers?["Authorization"] == "Bearer abc123")
        #expect(MockEndpoint(endpoint: "public", token: nil).headers?.isEmpty == true)
        #expect(MockEndpoint(endpoint: "empty", token: "").headers?["Authorization"] == "Bearer ")

        let e1 = MockEndpoint(endpoint: "test", token: "token")
        let e2 = MockEndpoint(endpoint: "test", token: "token")
        let e3 = MockEndpoint(endpoint: "different", token: "token")
        #expect(e1 == e2)
        #expect(e1 != e3)
    }

    @Test("MockEndpoint comprehensive testing")
    func mockEndpointComprehensiveTesting() throws {
        let endpoints = [
            MockEndpoint(endpoint: "users", token: "valid-token"),
            MockEndpoint(endpoint: "search", token: nil),
        ]
        for endpoint in endpoints {
            #expect(endpoint.url.absoluteString.contains(endpoint.path))
            #expect(endpoint.stringValue == endpoint.endpoint)
        }

        let e1 = MockEndpoint(endpoint: "test", token: "token1")
        let e2 = MockEndpoint(endpoint: "test", token: "token1")
        let e3 = MockEndpoint(endpoint: "test", token: "token2")
        let e4 = MockEndpoint(endpoint: "different", token: "token1")
        #expect(e1 == e2)
        #expect(e1 != e3)
        #expect(e1 != e4)
    }

    @Test("Endpoint equality and hashing")
    func endpointEquality() throws {
        let e1 = MockEndpoint(endpoint: "users/123", token: "token1")
        let e2 = MockEndpoint(endpoint: "users/123", token: "token1")
        let e3 = MockEndpoint(endpoint: "users/456", token: "token1")
        let e4 = MockEndpoint(endpoint: "users/123", token: "token2")
        #expect(e1 == e2)
        #expect(e1 != e3)
        #expect(e1 != e4)
    }

    // MARK: - Data Structure Tests

    @Test("MultipartData initialization")
    func multipartDataInitialization() throws {
        let parameters = ["key": "value"] as? [String: AnyObject]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters, fileKeyName: "file",
            fileURLs: [URL(fileURLWithPath: "/tmp/test.txt")])
        #expect(multipartData.parameters?.count == 1)
        #expect(multipartData.fileKeyName == "file")
        #expect(multipartData.fileURLs?.count == 1)
    }

    @Test("MultipartData stringValue")
    func multipartDataStringValue() throws {
        let parameters = ["name": "John Doe", "age": "30"] as [String: AnyObject]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters, fileKeyName: "uploads",
            fileURLs: [URL(fileURLWithPath: "/tmp/test.txt"), URL(fileURLWithPath: "/tmp/image.png")])

        let stringValue = multipartData.stringValue
        #expect(stringValue.contains("parameters:"))
        #expect(stringValue.contains("fileKeyName: uploads"))
        #expect(stringValue.contains("files:"))
        #expect(stringValue.contains("test.txt"))

        #expect(
            BaseAPI.MultipartData(parameters: nil, fileKeyName: "data", fileURLs: nil).stringValue
                == "fileKeyName: data")
    }

    @Test("MultipartData edge cases")
    func multipartDataEdgeCases() throws {
        #expect(
            BaseAPI.MultipartData(parameters: nil, fileKeyName: "empty", fileURLs: nil).stringValue
                == "fileKeyName: empty")
        #expect(
            BaseAPI.MultipartData(parameters: [:], fileKeyName: "test", fileURLs: nil).stringValue
                == "fileKeyName: test")
        #expect(
            BaseAPI.MultipartData(parameters: nil, fileKeyName: "files", fileURLs: []).stringValue
                == "fileKeyName: files")
    }

    @Test("EmptyResponse codable")
    func emptyResponseCodable() throws {
        let data = try JSONEncoder().encode(BaseAPI.EmptyResponse())
        let decoded = try JSONDecoder().decode(BaseAPI.EmptyResponse.self, from: data)
        #expect(type(of: decoded) == BaseAPI.EmptyResponse.self)
    }

    @Test("EmptyResponse comprehensive testing")
    func emptyResponseComprehensiveTesting() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(BaseAPI.EmptyResponse())
        let decoded = try JSONDecoder().decode(BaseAPI.EmptyResponse.self, from: data)
        #expect(type(of: decoded) == BaseAPI.EmptyResponse.self)

        encoder.outputFormatting = .prettyPrinted
        let prettyString = String(data: try encoder.encode(BaseAPI.EmptyResponse()), encoding: .utf8)
        #expect(prettyString?.contains("{") == true)
    }

    // MARK: - Extension Tests

    @Test("Data extension appendString")
    func dataExtensionAppendString() throws {
        var data = Data()
        data.appendString("Hello")
        data.appendString(" World")
        #expect(String(data: data, encoding: .utf8) == "Hello World")
    }

    @Test("Data extension decode with empty data")
    func dataExtensionDecodeEmptyResponse() throws {
        let result = try Data().decode(BaseAPI.EmptyResponse.self, decoder: JSONDecoder())
        #expect(type(of: result) == BaseAPI.EmptyResponse.self)
    }

    @Test("Data extension error scenarios")
    func dataExtensionErrorScenarios() throws {
        let decoder = JSONDecoder()
        #expect(throws: DecodingError.self) {
            _ = try "invalid json".data(using: .utf8)!.decode(TestResponse.self, decoder: decoder)
        }
        #expect(throws: DecodingError.self) {
            _ = try Data().decode(TestResponse.self, decoder: decoder)
        }
    }

    @Test("Response data decoding")
    func responseDataDecoding() throws {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()
        let testResponse = TestResponse(id: "123", status: "success")
        let encodedData = try encoder.encode(testResponse)

        let decoded = try encodedData.decode(
            TestResponse.self, decoder: decoder,
            endpoint: "test", method: "GET")
        #expect(decoded.id == "123")
        #expect(decoded.status == "success")

        let emptyDecoded = try Data().decode(BaseAPI.EmptyResponse.self, decoder: decoder)
        #expect(type(of: emptyDecoded) == BaseAPI.EmptyResponse.self)
    }

    @Test("URLRequest JSON headers addition")
    func urlRequestJSONHeaders() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.addJSONHeaders(additionalHeaders: ["Authorization": "Bearer token123", "X-Custom": "val"])
        // Content-Type is not set by addJSONHeaders — it's applied per-body-type in the builder.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
    }

    @Test("URLRequest extensions error handling")
    func urlRequestExtensionsErrorHandling() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.addJSONHeaders(additionalHeaders: [:])
        // addJSONHeaders only sets Accept; Content-Type is absent on body-less requests.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        request.addJSONHeaders(additionalHeaders: ["Content-Type": "application/custom"])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/custom")
    }

    @Test("URLRequest JSON body addition")
    func urlRequestJSONBody() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let encoder = JSONEncoder()
        let logger = MockLogger()

        try request.addJSONBody(TestRequest(name: "Test", value: 42), encoder: encoder)

        #expect(request.httpBody != nil)
        if let bodyData = request.httpBody {
            let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            #expect(json?["name"] as? String == "Test")
            #expect(json?["value"] as? Int == 42)
        }

        var request2 = URLRequest(url: URL(string: "https://example.com")!)
        let nilBody: TestRequest? = nil
        try request2.addJSONBody(nilBody, encoder: encoder)
        #expect(request2.httpBody == nil)
    }

    @Test("URLRequest multipart data creation")
    func urlRequestMultipartData() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.txt")
        try "Test file content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let multipartData = BaseAPI.MultipartData(
            parameters: ["description": "Test upload"] as [String: AnyObject],
            fileKeyName: "file", fileURLs: [tempURL])

        try request.addMultipartData(data: multipartData)

        #expect(request.httpBody != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
        #expect(request.timeoutInterval == 60)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)

        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            #expect(bodyString.contains("Test file content"))
            #expect(bodyString.contains("Test upload"))
        }
    }

    @Test("URLSession mimeType functionality")
    func urlSessionMimeTypeFunctionality() throws {
        #expect(!URLSession.mimeTypeForPath("txt").isEmpty)
        #expect(!URLSession.mimeTypeForPath("json").isEmpty)
        #expect(URLSession.mimeTypeForPath("unknown") == "application/octet-stream")
    }

    // MARK: - HTTPMethod Tests

    @Test("HTTPMethod cases")
    func httpMethodCases() throws {
        #expect(BaseAPI.HTTPMethod.get.rawValue == "GET")
        #expect(BaseAPI.HTTPMethod.post.rawValue == "POST")
        #expect(BaseAPI.HTTPMethod.put.rawValue == "PUT")
        #expect(BaseAPI.HTTPMethod.patch.rawValue == "PATCH")
        #expect(BaseAPI.HTTPMethod.delete.rawValue == "DELETE")
        #expect(BaseAPI.HTTPMethod.allCases.count == 7)
    }

    @Test("HTTPMethod comprehensive coverage")
    func httpMethodComprehensiveCoverage() throws {
        let methods = BaseAPI.HTTPMethod.allCases
        for method in methods {
            #expect(!method.rawValue.isEmpty)
            #expect(method.rawValue.allSatisfy { $0.isUppercase })
        }
        #expect(Set(methods.map { $0.rawValue }) == ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
    }

    @Test("HTTPMethod includes HEAD and OPTIONS")
    func httpMethodHeadAndOptions() throws {
        #expect(BaseAPI.HTTPMethod.head.rawValue == "HEAD")
        #expect(BaseAPI.HTTPMethod.options.rawValue == "OPTIONS")
        #expect(BaseAPI.HTTPMethod.allCases.count == 7)
    }

    // MARK: - Analytics Tests

    @Test("Analytics data tracking")
    func analyticsDataTracking() throws {
        let analytics = MockAnalytics()
        let startTime = Date()
        let endTime = Date().addingTimeInterval(0.5)

        analytics.addAnalytics(
            endpoint: "/api/users", method: "GET", startTime: startTime,
            endTime: endTime, success: true, statusCode: 200, error: nil)
        analytics.addAnalytics(
            endpoint: "/api/users", method: "POST", startTime: startTime,
            endTime: endTime, success: false, statusCode: 422, error: "Validation failed")

        #expect(analytics.analyticsData.count == 2)
        #expect(analytics.analyticsData[0].success == true)
        #expect(analytics.analyticsData[0].statusCode == 200)
        #expect(analytics.analyticsData[1].success == false)
        #expect(analytics.analyticsData[1].error == "Validation failed")
    }

    // MARK: - BaseAPIClient Configuration Tests

    @Test("BaseAPIClient custom configuration")
    func baseAPIClientCustomConfiguration() throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var unauthorizedCount = 0
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: sessionConfig,
            encoder: encoder,
            decoder: decoder,
            analytics: MockAnalytics(),
            logger: MockLogger(),
            unauthorizedHandler: { _ in unauthorizedCount += 1 }
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
        #expect(unauthorizedCount == 0)
    }

    @Test("Request body encoding")
    func requestBodyEncoding() throws {
        let data = try JSONEncoder().encode(TestRequest(name: "John Doe", value: 42))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["name"] as? String == "John Doe")
        #expect(json?["value"] as? Int == 42)
    }

    @Test("JSON encoder/decoder configuration")
    func jsonCoderConfiguration() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        struct DateModel: Codable {
            let timestamp: Date
            let name: String
        }

        let testDate = Date(timeIntervalSince1970: 1_640_995_200)
        let encodedData = try encoder.encode(DateModel(timestamp: testDate, name: "test"))
        let decodedModel = try decoder.decode(DateModel.self, from: encodedData)

        #expect(decodedModel.name == "test")
        #expect(abs(decodedModel.timestamp.timeIntervalSince1970 - testDate.timeIntervalSince1970) < 1.0)
        #expect(String(data: encodedData, encoding: .utf8)!.contains("\n"))
    }

    // MARK: - Request Interceptor Tests

    @Test("Client initializes with interceptor")
    func clientInitializesWithInterceptor() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            interceptor: MockInterceptor(additionalHeaders: ["Authorization": "Bearer token"]))
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client initializes without interceptor")
    func clientInitializesWithoutInterceptor() throws {
        #expect(type(of: BaseAPI.BaseAPIClient<MockEndpoint>()) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("MockInterceptor adapts request with headers")
    func mockInterceptorAdaptsRequest() async throws {
        let interceptor = MockInterceptor(additionalHeaders: [
            "Authorization": "Bearer my-token", "X-API-Key": "key-123",
        ])
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await interceptor.adapt(request)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "key-123")
    }

    @Test("FailingInterceptor throws error")
    func failingInterceptorThrowsError() async {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await FailingInterceptor().adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    // MARK: - Interceptor Chain Tests

    @Test("InterceptorChain applies interceptors in order")
    func interceptorChainAppliesInOrder() async throws {
        let chain = BaseAPI.InterceptorChain([
            MockInterceptor(additionalHeaders: ["X-First": "1"]),
            MockInterceptor(additionalHeaders: ["X-Second": "2"]),
        ])
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await chain.adapt(request)
        #expect(request.value(forHTTPHeaderField: "X-First") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Second") == "2")
    }

    @Test("InterceptorChain later interceptor overwrites same header")
    func interceptorChainOverwrites() async throws {
        let chain = BaseAPI.InterceptorChain([
            MockInterceptor(additionalHeaders: ["X-Token": "old"]),
            MockInterceptor(additionalHeaders: ["X-Token": "new"]),
        ])
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await chain.adapt(request)
        #expect(request.value(forHTTPHeaderField: "X-Token") == "new")
    }

    @Test("InterceptorChain with empty interceptors is a no-op")
    func interceptorChainEmpty() async throws {
        let original = URLRequest(url: URL(string: "https://example.com")!)
        let adapted = try await BaseAPI.InterceptorChain([]).adapt(original)
        #expect(adapted.url == original.url)
        #expect(adapted.allHTTPHeaderFields == original.allHTTPHeaderFields)
    }

    @Test("InterceptorChain propagates first failing interceptor")
    func interceptorChainPropagatesFailure() async {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await BaseAPI.InterceptorChain([FailingInterceptor()]).adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    @Test("InterceptorChain stops at first failing interceptor")
    func interceptorChainStopsAtFailure() async {
        let chain = BaseAPI.InterceptorChain([
            FailingInterceptor(), MockInterceptor(additionalHeaders: ["X-Ran": "yes"]),
        ])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await chain.adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    // MARK: - RetryDecision Tests

    @Test("RetryDecision doNotRetry")
    func retryDecisionDoNotRetry() {
        if case .doNotRetry = BaseAPI.RetryDecision.doNotRetry { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryDecision retry with delay")
    func retryDecisionRetryWithDelay() {
        if case .retry(let delay) = BaseAPI.RetryDecision.retry(delay: 2.5) {
            #expect(delay == 2.5)
        } else {
            #expect(Bool(false))
        }
    }

    @Test("RetryDecision retry with zero delay")
    func retryDecisionRetryZeroDelay() {
        if case .retry(let delay) = BaseAPI.RetryDecision.retry(delay: 0) {
            #expect(delay == 0)
        } else {
            #expect(Bool(false))
        }
    }

    @Test("Default retry implementation returns doNotRetry")
    func defaultRetryReturnsDoNotRetry() async {
        let decision = await MockInterceptor(additionalHeaders: [:]).retry(
            URLRequest(url: URL(string: "https://example.com")!),
            dueTo: BaseAPI.APIError.unknown, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("InterceptorChain retry returns doNotRetry when no interceptor retries")
    func interceptorChainRetryNone() async {
        let chain = BaseAPI.InterceptorChain([MockInterceptor(additionalHeaders: [:])])
        let decision = await chain.retry(
            URLRequest(url: URL(string: "https://example.com")!),
            dueTo: BaseAPI.APIError.unknown, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("InterceptorChain retry returns first retry decision")
    func interceptorChainRetryFirstWins() async {
        struct RetryingInterceptor: BaseAPI.RequestInterceptor {
            let delay: TimeInterval
            func adapt(_ request: URLRequest) async throws -> URLRequest { request }
            func retry(_ request: URLRequest, dueTo error: Error, attemptCount: Int) async -> BaseAPI.RetryDecision {
                .retry(delay: delay)
            }
        }
        let chain = BaseAPI.InterceptorChain([RetryingInterceptor(delay: 1.0), RetryingInterceptor(delay: 99.0)])
        let decision = await chain.retry(
            URLRequest(url: URL(string: "https://example.com")!),
            dueTo: BaseAPI.APIError.unknown, attemptCount: 1)
        if case .retry(let delay) = decision { #expect(delay == 1.0) } else { #expect(Bool(false)) }
    }

    // MARK: - Client Interceptors Array Tests

    @Test("Client initialises with interceptors array")
    func clientInitializesWithInterceptorsArray() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [
            MockInterceptor(additionalHeaders: ["X-App": "test"]),
            MockInterceptor(additionalHeaders: ["X-Version": "1"]),
        ])
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client initialises with empty interceptors array")
    func clientInitializesWithEmptyInterceptors() throws {
        #expect(
            type(of: BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [])) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Single-interceptor convenience init is equivalent to array init")
    func singleInterceptorConvenienceInit() throws {
        let interceptor = MockInterceptor(additionalHeaders: ["X-Auth": "token"])
        let clientA = BaseAPI.BaseAPIClient<MockEndpoint>(interceptor: interceptor)
        let clientB = BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [interceptor])
        #expect(type(of: clientA) == type(of: clientB))
    }

    // MARK: - ResponseValidator Tests

    @Test("StatusCodeValidator accepts 2xx responses")
    func statusCodeValidatorAccepts2xx() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for code in [200, 201, 204, 299] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            try validator.validate(response, data: Data(), for: request)
        }
    }

    @Test("StatusCodeValidator rejects non-2xx responses")
    func statusCodeValidatorRejectsNon2xx() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for code in [400, 401, 404, 422, 500] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            do {
                try validator.validate(response, data: Data(), for: request)
                #expect(Bool(false), "Should have thrown for \(code)")
            } catch let error as BaseAPI.APIError {
                if case .serverError(_, let errorCode, _) = error {
                    #expect(errorCode == code)
                } else {
                    #expect(Bool(false))
                }
            }
        }
    }

    @Test("StatusCodeValidator includes x-request-id from response headers")
    func statusCodeValidatorIncludesRequestId() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil,
            headerFields: ["x-request-id": "req-abc-123"])!
        do {
            try validator.validate(response, data: Data(), for: request)
            #expect(Bool(false))
        } catch let error as BaseAPI.APIError {
            if case .serverError(_, _, let requestID) = error {
                #expect(requestID == "req-abc-123")
            } else {
                #expect(Bool(false))
            }
        }
    }

    @Test("StatusCodeValidator uses N/A when x-request-id header is absent")
    func statusCodeValidatorFallbackRequestId() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        do {
            try validator.validate(response, data: Data(), for: request)
            #expect(Bool(false))
        } catch let error as BaseAPI.APIError {
            if case .serverError(_, _, let requestID) = error {
                #expect(requestID == "N/A")
            } else {
                #expect(Bool(false))
            }
        }
    }

    @Test("AcceptedStatusCodesValidator accepts only specified codes")
    func acceptedStatusCodesValidatorAcceptsSpecified() throws {
        let validator = BaseAPI.AcceptedStatusCodesValidator([200, 201, 304])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for code in [200, 201, 304] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            try validator.validate(response, data: Data(), for: request)
        }
    }

    @Test("AcceptedStatusCodesValidator rejects unspecified codes")
    func acceptedStatusCodesValidatorRejectsOthers() throws {
        let validator = BaseAPI.AcceptedStatusCodesValidator([200, 201])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for code in [204, 400, 500] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            #expect(throws: (any Error).self) { try validator.validate(response, data: Data(), for: request) }
        }
    }

    @Test("AcceptedStatusCodesValidator with single code")
    func acceptedStatusCodesValidatorSingleCode() throws {
        let validator = BaseAPI.AcceptedStatusCodesValidator([200])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let ok = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try validator.validate(ok, data: Data(), for: request)
        let notOk = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 201, httpVersion: nil, headerFields: nil)!
        #expect(throws: (any Error).self) { try validator.validate(notOk, data: Data(), for: request) }
    }

    @Test("Custom ResponseValidator protocol conformance")
    func customResponseValidatorConformance() throws {
        struct NoOpValidator: BaseAPI.ResponseValidator {
            func validate(_ response: HTTPURLResponse, data: Data, for request: URLRequest) throws {}
        }
        struct AlwaysFailValidator: BaseAPI.ResponseValidator {
            func validate(_ response: HTTPURLResponse, data: Data, for request: URLRequest) throws {
                throw BaseAPI.APIError.unknown
            }
        }
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        try NoOpValidator().validate(response, data: Data(), for: request)
        #expect(throws: (any Error).self) { try AlwaysFailValidator().validate(response, data: Data(), for: request) }
    }

    @Test("Client init with custom validators")
    func clientInitWithCustomValidators() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(validators: [
            BaseAPI.AcceptedStatusCodesValidator([200, 201, 204])
        ])
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    // MARK: - BackoffStrategy Tests

    @Test("BackoffStrategy.none always returns zero delay")
    func backoffNoneReturnsZero() {
        let strategy = BaseAPI.BackoffStrategy.none
        for attempt in 1...5 { #expect(strategy.delay(for: attempt) == 0) }
    }

    @Test("BackoffStrategy.constant always returns fixed delay")
    func backoffConstantReturnsFixed() {
        let strategy = BaseAPI.BackoffStrategy.constant(2.5)
        for attempt in 1...5 { #expect(strategy.delay(for: attempt) == 2.5) }
    }

    @Test("BackoffStrategy.exponential doubles delay each attempt")
    func backoffExponentialDoubles() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 1, multiplier: 2, maxDelay: 60)
        #expect(strategy.delay(for: 1) == 1.0)
        #expect(strategy.delay(for: 2) == 2.0)
        #expect(strategy.delay(for: 3) == 4.0)
        #expect(strategy.delay(for: 4) == 8.0)
        #expect(strategy.delay(for: 5) == 16.0)
    }

    @Test("BackoffStrategy.exponential respects maxDelay cap")
    func backoffExponentialCapsAtMaxDelay() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 1, multiplier: 2, maxDelay: 5)
        #expect(strategy.delay(for: 3) == 4.0)
        #expect(strategy.delay(for: 4) == 5.0)
        #expect(strategy.delay(for: 5) == 5.0)
    }

    @Test("BackoffStrategy.exponential with custom base and multiplier")
    func backoffExponentialCustom() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 0.5, multiplier: 3, maxDelay: 100)
        #expect(strategy.delay(for: 1) == 0.5)
        #expect(strategy.delay(for: 2) == 1.5)
        #expect(strategy.delay(for: 3) == 4.5)
    }

    // MARK: - RetryPolicy Tests

    @Test("RetryPolicy retries on retryable status codes")
    func retryPolicyRetriesOnRetryableStatusCodes() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .none, retryableStatusCodes: [500, 503])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let decision = await policy.retry(
            request, dueTo: BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x"), attemptCount: 1
        )
        if case .retry(let delay) = decision { #expect(delay == 0) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy does not retry on non-retryable status codes")
    func retryPolicySkipsNonRetryableStatusCodes() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 404, httpVersion: nil, headerFields: nil)!
        let decision = await policy.retry(
            request, dueTo: BaseAPI.APIError.serverError(response: response, code: 404, requestID: "x"), attemptCount: 1
        )
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy stops after maxAttempts")
    func retryPolicyStopsAtMaxAttempts() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let decision = await policy.retry(
            request, dueTo: BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x"), attemptCount: 3
        )
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy retries network errors when retryNetworkErrors is true")
    func retryPolicyRetriesNetworkErrors() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .constant(1), retryNetworkErrors: true)
        let decision = await policy.retry(
            URLRequest(url: URL(string: "https://example.com")!), dueTo: BaseAPI.APIError.networkError("timeout"),
            attemptCount: 1)
        if case .retry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy does not retry network errors by default")
    func retryPolicySkipsNetworkErrorsByDefault() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3)
        let decision = await policy.retry(
            URLRequest(url: URL(string: "https://example.com")!), dueTo: BaseAPI.APIError.networkError("timeout"),
            attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy.adapt is a no-op pass-through")
    func retryPolicyAdaptIsNoOp() async throws {
        let policy = BaseAPI.RetryPolicy()
        var request = URLRequest(url: URL(string: "https://example.com")!)
        request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
        let adapted = try await policy.adapt(request)
        #expect(adapted.url == request.url)
        #expect(adapted.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test("RetryPolicy default retryable status codes")
    func retryPolicyDefaultStatusCodes() async {
        let policy = BaseAPI.RetryPolicy()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        for code in [429, 500, 502, 503, 504] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!, statusCode: code, httpVersion: nil, headerFields: nil)!
            let decision = await policy.retry(
                request, dueTo: BaseAPI.APIError.serverError(response: response, code: code, requestID: "x"),
                attemptCount: 1)
            if case .retry = decision {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected retry for \(code)")
            }
        }
    }

    @Test("RetryPolicy maxAttempts clamped to minimum 1")
    func retryPolicyMinAttempts() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 0)
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let decision = await policy.retry(
            request, dueTo: BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x"), attemptCount: 1
        )
        if case .doNotRetry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy uses exponential backoff delay")
    func retryPolicyExponentialDelay() async {
        let policy = BaseAPI.RetryPolicy(
            maxAttempts: 5, backoff: .exponential(base: 1, multiplier: 2, maxDelay: 60), retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500, httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x")

        let d1 = await policy.retry(request, dueTo: error, attemptCount: 1)
        let d2 = await policy.retry(request, dueTo: error, attemptCount: 2)
        let d3 = await policy.retry(request, dueTo: error, attemptCount: 3)
        if case .retry(let delay) = d1 { #expect(delay == 1.0) } else { #expect(Bool(false)) }
        if case .retry(let delay) = d2 { #expect(delay == 2.0) } else { #expect(Bool(false)) }
        if case .retry(let delay) = d3 { #expect(delay == 4.0) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy composes correctly in InterceptorChain")
    func retryPolicyInInterceptorChain() async {
        let chain = BaseAPI.InterceptorChain([
            MockInterceptor(additionalHeaders: ["Authorization": "Bearer tok"]),
            BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .constant(0.5), retryableStatusCodes: [503]),
        ])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 503, httpVersion: nil, headerFields: nil)!
        let decision = await chain.retry(
            request, dueTo: BaseAPI.APIError.serverError(response: response, code: 503, requestID: "x"), attemptCount: 1
        )
        if case .retry(let delay) = decision { #expect(delay == 0.5) } else { #expect(Bool(false)) }
    }

    @Test("Client initialises with RetryPolicy in interceptors array")
    func clientInitWithRetryPolicy() {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [
            MockInterceptor(additionalHeaders: ["X-App": "test"]),
            BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .exponential(base: 1, multiplier: 2, maxDelay: 30)),
        ])
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }
}
