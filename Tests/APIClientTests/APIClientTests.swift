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
        let errors: [BaseAPI.APIError] = [.encodingFailed, .networkError(URLError(.timedOut)), .unknown]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("APIError client error classification")
    func apiErrorClientErrorClassification() throws {
        #expect(BaseAPI.APIError.encodingFailed.isClientError == true)
        #expect(BaseAPI.APIError.decodingFailed(response: HTTPURLResponse(), error: "test").isClientError == true)
        #expect(BaseAPI.APIError.networkError(URLError(.notConnectedToInternet)).isClientError == false)
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
        #expect(BaseAPI.APIError.networkError(URLError(.timedOut)).getResponse() == nil)
    }

    @Test("APIError networkError preserves URLError code")
    func apiErrorNetworkErrorPreservesURLErrorCode() throws {
        let urlError = URLError(.notConnectedToInternet)
        let apiError = BaseAPI.APIError.networkError(urlError)
        if case .networkError(let underlying) = apiError {
            #expect(underlying.code == .notConnectedToInternet)
        } else {
            Issue.record("Expected .networkError case")
        }
        #expect(apiError.errorDescription?.isEmpty == false)
    }

    @Test("APIError localized descriptions")
    func apiErrorLocalizedDescriptions() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 400,
            httpVersion: nil, headerFields: nil)!

        let errors: [BaseAPI.APIError] = [
            .encodingFailed, .networkError(URLError(.timedOut)),
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

    // MARK: - MultipartFormData Tests

    @Test("MultipartFormData append in-memory data field")
    func multipartFormDataAppendData() throws {
        let form = BaseAPI.MultipartFormData()
        let value = "hello".data(using: .utf8)!
        form.append(value, name: "greeting")
        let (body, _) = try form.encode()
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("name=\"greeting\""))
        #expect(bodyString.contains("hello"))
    }

    @Test("MultipartFormData append data with filename and mimeType")
    func multipartFormDataAppendDataWithFilename() throws {
        let form = BaseAPI.MultipartFormData()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header (valid ASCII range for test purposes)
        form.append(imageData, name: "avatar", fileName: "photo.png", mimeType: "image/png")
        let (body, _) = try form.encode()
        // Headers are ASCII text; only inspect the latin-1 representable portion
        let bodyString = String(bytes: body, encoding: .isoLatin1)!
        #expect(bodyString.contains("name=\"avatar\""))
        #expect(bodyString.contains("filename=\"photo.png\""))
        #expect(bodyString.contains("image/png"))
    }

    @Test("MultipartFormData append file URL")
    func multipartFormDataAppendFileURL() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("upload.txt")
        try "file contents".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let form = BaseAPI.MultipartFormData()
        try form.append(fileURL: tempURL, name: "attachment")
        let (body, _) = try form.encode()
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("name=\"attachment\""))
        #expect(bodyString.contains("file contents"))
        #expect(bodyString.contains("filename=\"upload.txt\""))
    }

    @Test("MultipartFormData append file URL with explicit MIME type")
    func multipartFormDataAppendFileURLExplicitMIME() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("data.bin")
        try Data([0x01, 0x02]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let form = BaseAPI.MultipartFormData()
        try form.append(fileURL: tempURL, name: "file", fileName: "renamed.bin", mimeType: "application/octet-stream")
        let (body, _) = try form.encode()
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("filename=\"renamed.bin\""))
        #expect(bodyString.contains("application/octet-stream"))
    }

    @Test("MultipartFormData append InputStream")
    func multipartFormDataAppendInputStream() throws {
        let content = "stream content".data(using: .utf8)!
        let stream = InputStream(data: content)
        let form = BaseAPI.MultipartFormData()
        form.append(stream, length: UInt64(content.count), name: "data", fileName: "data.txt", mimeType: "text/plain")
        let (body, _) = try form.encode()
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("name=\"data\""))
        #expect(bodyString.contains("stream content"))
    }

    @Test("MultipartFormData Content-Type header includes boundary")
    func multipartFormDataContentTypeHeader() throws {
        let form = BaseAPI.MultipartFormData()
        form.append("value".data(using: .utf8)!, name: "key")
        let (_, contentType) = try form.encode()
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        #expect(contentType.count > "multipart/form-data; boundary=".count)
    }

    @Test("MultipartFormData MIME type inferred from extension")
    func multipartFormDataMIMEInference() throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("image.png")
        try Data().write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let form = BaseAPI.MultipartFormData()
        try form.append(fileURL: tempURL, name: "img")
        let (body, _) = try form.encode()
        let bodyString = String(data: body, encoding: .utf8)!
        #expect(bodyString.contains("image/png"))
    }

    @Test("MultipartFormData append missing file URL throws")
    func multipartFormDataMissingFileThrows() throws {
        let form = BaseAPI.MultipartFormData()
        #expect(throws: (any Error).self) {
            try form.append(fileURL: URL(fileURLWithPath: "/nonexistent/file.txt"), name: "file")
        }
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

    @Test("URLRequest multipart encoding sets Content-Type and body")
    func urlRequestMultipartEncoding() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.txt")
        try "Test file content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let form = BaseAPI.MultipartFormData()
        form.append("Test upload".data(using: .utf8)!, name: "description")
        try form.append(fileURL: tempURL, name: "file")
        try request.applyMultipart(form)

        #expect(request.httpBody != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        if let bodyString = request.httpBody.flatMap({ String(data: $0, encoding: .utf8) }) {
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
    func baseAPIClientCustomConfiguration() async throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let unauthorizedCount = ActorBox<Int>(0)
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: sessionConfig,
            encoder: encoder,
            decoder: decoder,
            analytics: MockAnalytics(),
            logger: MockLogger(),
            unauthorizedHandler: { _ in Task { await unauthorizedCount.set(await unauthorizedCount.value + 1) } }
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
        #expect(await unauthorizedCount.value == 0)
    }

    @Test("Request body encoding")
    func requestBodyEncoding() throws {
        let data = try JSONEncoder().encode(TestRequest(name: "John Doe", value: 42))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["name"] as? String == "John Doe")
        #expect(json?["value"] as? Int == 42)
    }

    // MARK: - AnyEncodable Tests

    @Test("AnyEncodable round-trips a simple struct")
    func anyEncodableRoundTripsSimpleStruct() throws {
        let value = TestRequest(name: "Alice", value: 7)
        let data = try JSONEncoder().encode(AnyEncodable(value))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["name"] as? String == "Alice")
        #expect(json?["value"] as? Int == 7)
    }

    @Test("AnyEncodable round-trips a nested struct")
    func anyEncodableRoundTripsNestedStruct() throws {
        struct Outer: Encodable {
            let inner: TestRequest
            let label: String
        }
        let value = Outer(inner: TestRequest(name: "Bob", value: 3), label: "test")
        let data = try JSONEncoder().encode(AnyEncodable(value))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["label"] as? String == "test")
        let inner = json?["inner"] as? [String: Any]
        #expect(inner?["name"] as? String == "Bob")
    }

    @Test("AnyEncodable works with any Encodable existential")
    func anyEncodableWorksWithExistential() throws {
        let values: [any Encodable] = [TestRequest(name: "C", value: 1), TestResponse(id: "x", status: "ok")]
        for value in values {
            let data = try JSONEncoder().encode(AnyEncodable(value))
            #expect(!data.isEmpty)
        }
    }

    @Test("AnyEncodable propagates encoding failure")
    func anyEncodablePropagatesFailure() throws {
        #expect(throws: (any Error).self) {
            _ = try JSONEncoder().encode(AnyEncodable(UnencodableBody()))
        }
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
            URLRequest(url: URL(string: "https://example.com")!),
            dueTo: BaseAPI.APIError.networkError(URLError(.timedOut)),
            attemptCount: 1)
        if case .retry = decision { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy does not retry network errors by default")
    func retryPolicySkipsNetworkErrorsByDefault() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3)
        let decision = await policy.retry(
            URLRequest(url: URL(string: "https://example.com")!),
            dueTo: BaseAPI.APIError.networkError(URLError(.timedOut)),
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
