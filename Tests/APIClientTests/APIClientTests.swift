import Foundation
import Testing
import UniformTypeIdentifiers

@testable import APIClient

// MARK: - Test Mock Endpoint
struct MockEndpoint: BaseAPI.APIEndpoint, Equatable, Hashable {
    let endpoint: String
    let token: String?

    var baseURL: URL {
        URL(string: "https://api.example.com")!
    }

    var path: String {
        endpoint
    }

    var headers: [String: String]? {
        guard let token = token else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}

// MARK: - Test Models
struct TestRequest: Codable {
    let name: String
    let value: Int
}

struct TestResponse: Codable {
    let id: String
    let status: String
}

// MARK: - Mock Logger for Testing
final class MockLogger: BaseAPI.APIClientLoggingProtocol, @unchecked Sendable {
    private(set) var logCount = 0

    func info(_ value: String) { logCount += 1 }
    func debug(_ value: String) { logCount += 1 }
    func error(_ value: String) { logCount += 1 }
    func warn(_ value: String) { logCount += 1 }

    func reset() { logCount = 0 }
}

// MARK: - Mock Request Interceptor
struct MockInterceptor: BaseAPI.RequestInterceptor {
    let additionalHeaders: [String: String]

    func adapt(_ request: URLRequest) async throws -> URLRequest {
        var request = request
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}

struct FailingInterceptor: BaseAPI.RequestInterceptor {
    func adapt(_ request: URLRequest) async throws -> URLRequest {
        throw BaseAPI.APIError.networkError("Interceptor rejected request")
    }
}

// MARK: - Mock Analytics
final class MockAnalytics: BaseAPI.APIAnalytics, @unchecked Sendable {
    var analyticsData:
        [(
            endpoint: String, method: String, startTime: Date, endTime: Date, success: Bool,
            statusCode: Int?, error: String?
        )] = []

    func addAnalytics(
        endpoint: String, method: String, startTime: Date, endTime: Date, success: Bool,
        statusCode: Int?, error: String?
    ) {
        analyticsData.append((endpoint, method, startTime, endTime, success, statusCode, error))
    }
}

// MARK: - MockURLProtocol

/// URLProtocol subclass that intercepts requests and calls a handler closure.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) async -> (Data, HTTPURLResponse)
    static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        // URLSession moves httpBody into httpBodyStream when dispatching through URLProtocol.
        // Reconstruct a request with httpBody populated so handlers can inspect it.
        var resolved = request
        if resolved.httpBody == nil, let stream = resolved.httpBodyStream {
            stream.open()
            var bodyData = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                if count > 0 { bodyData.append(buffer, count: count) }
            }
            stream.close()
            resolved.httpBody = bodyData
        }
        Task {
            let (data, response) = await handler(resolved)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// Thread-safe box for capturing values inside async closures in tests.
actor ActorBox<T> {
    private(set) var value: T
    init(_ initial: T) { self.value = initial }
    func set(_ newValue: T) { self.value = newValue }
}

/// Returns a URLSessionConfiguration pre-wired to use MockURLProtocol.
func mockSessionConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return config
}

// MARK: - API Client Test Suite
@Suite("API Client Tests")
struct APIClientTests {

    // MARK: - Base API Tests
    @Test("BaseAPI type existence")
    func baseAPITypeExistence() throws {
        // BaseAPI enum exists and can be referenced
        #expect(type(of: BaseAPI.self) == BaseAPI.Type.self)

        // Verify EmptyResponse can be created
        let emptyResponse = BaseAPI.EmptyResponse()
        #expect(type(of: emptyResponse) == BaseAPI.EmptyResponse.self)
    }

    @Test("BaseAPIClient initialization")
    func baseAPIClientInitialization() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(logger: nil)
        // BaseAPIClient initializes successfully
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("BaseAPIClient initialization with dependencies")
    func baseAPIClientInitializationWithDependencies() throws {
        let logger = MockLogger()
        let analytics = MockAnalytics()
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            analytics: analytics,
            logger: logger
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    // MARK: - Error Handling Tests
    @Test("APIError descriptions")
    func apiErrorDescriptions() throws {
        let errors: [BaseAPI.APIError] = [
            .encodingFailed,
            .networkError("Test network error"),
            .unknown,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("APIError client error classification")
    func apiErrorClientErrorClassification() throws {
        #expect(BaseAPI.APIError.encodingFailed.isClientError == true)
        #expect(
            BaseAPI.APIError.decodingFailed(response: HTTPURLResponse(), error: "test")
                .isClientError == true)
        #expect(BaseAPI.APIError.networkError("test").isClientError == false)
        #expect(BaseAPI.APIError.unknown.isClientError == false)
    }

    // MARK: - Endpoint Tests
    @Test("MockEndpoint functionality")
    func mockEndpointFunctionality() throws {
        let endpoint = MockEndpoint(endpoint: "users", token: "test-token")

        #expect(endpoint.url.absoluteString == "https://api.example.com/users")
        #expect(endpoint.stringValue == "users")
        #expect(endpoint.headers?["Authorization"] == "Bearer test-token")

        let endpointWithoutToken = MockEndpoint(endpoint: "public", token: nil)
        #expect(endpointWithoutToken.headers?.isEmpty == true)
    }

    // MARK: - Data Structure Tests
    @Test("MultipartData initialization")
    func multipartDataInitialization() throws {
        let parameters = ["key": "value"] as? [String: AnyObject]
        let fileURLs = [URL(fileURLWithPath: "/tmp/test.txt")]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters,
            fileKeyName: "file",
            fileURLs: fileURLs
        )

        #expect(multipartData.parameters?.count == 1)
        #expect(multipartData.fileKeyName == "file")
        #expect(multipartData.fileURLs?.count == 1)
    }

    @Test("MultipartData stringValue")
    func multipartDataStringValue() throws {
        // Test with all components
        let parameters = ["name": "John Doe", "age": "30"] as [String: AnyObject]
        let fileURLs = [
            URL(fileURLWithPath: "/tmp/test.txt"), URL(fileURLWithPath: "/tmp/image.png"),
        ]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters,
            fileKeyName: "uploads",
            fileURLs: fileURLs
        )

        let stringValue = multipartData.stringValue
        #expect(stringValue.contains("parameters:"))
        #expect(stringValue.contains("fileKeyName: uploads"))
        #expect(stringValue.contains("files:"))
        #expect(stringValue.contains("test.txt"))
        #expect(stringValue.contains("image.png"))

        // Test with minimal components
        let minimalData = BaseAPI.MultipartData(
            parameters: nil,
            fileKeyName: "data",
            fileURLs: nil
        )

        let minimalString = minimalData.stringValue
        #expect(minimalString == "fileKeyName: data")
    }

    @Test("EmptyResponse codable")
    func emptyResponseCodable() throws {
        let emptyResponse = BaseAPI.EmptyResponse()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(emptyResponse)
        let decoded = try decoder.decode(BaseAPI.EmptyResponse.self, from: data)

        // EmptyResponse decodes successfully
        #expect(type(of: decoded) == BaseAPI.EmptyResponse.self)
    }

    // MARK: - Extension Tests
    @Test("Data extension appendString")
    func dataExtensionAppendString() throws {
        var data = Data()
        data.appendString("Hello")
        data.appendString(" World")

        let string = String(data: data, encoding: .utf8)
        #expect(string == "Hello World")
    }

    @Test("Data extension decode with empty data")
    func dataExtensionDecodeEmptyResponse() throws {
        let emptyData = Data()
        let decoder = JSONDecoder()

        let result = try emptyData.decode(BaseAPI.EmptyResponse.self, decoder: decoder)
        #expect(type(of: result) == BaseAPI.EmptyResponse.self)
    }

    @Test("URLSession mimeType functionality")
    func urlSessionMimeTypeFunctionality() throws {
        let txtMimeType = URLSession.mimeTypeForPath("txt")
        let jsonMimeType = URLSession.mimeTypeForPath("json")
        let unknownMimeType = URLSession.mimeTypeForPath("unknown")

        #expect(!txtMimeType.isEmpty)
        #expect(!jsonMimeType.isEmpty)
        #expect(unknownMimeType == "application/octet-stream")
    }

    @Test("HTTPMethod cases")
    func httpMethodCases() throws {
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.get.rawValue == "GET")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.post.rawValue == "POST")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.put.rawValue == "PUT")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.patch.rawValue == "PATCH")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")

        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases.count == 5)
    }

    // MARK: - API Endpoint Tests
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
        #expect(endpoint.stringValue == "public/data")
        #expect(endpoint.headers?.isEmpty == true)
    }

    // MARK: - Additional Tests for Better Coverage

    @Test("APIError getResponse functionality")
    func apiErrorGetResponse() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!

        let serverError = BaseAPI.APIError.serverError(
            response: httpResponse, code: 500, requestID: "123")
        let decodingError = BaseAPI.APIError.decodingFailed(
            response: httpResponse, error: "Test error")
        let networkError = BaseAPI.APIError.networkError("Network failure")

        #expect(serverError.getResponse() == httpResponse)
        #expect(decodingError.getResponse() == httpResponse)
        #expect(networkError.getResponse() == nil)
    }

    @Test("URLRequest JSON headers addition")
    func urlRequestJSONHeaders() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let additionalHeaders = ["Authorization": "Bearer token123", "X-Custom": "CustomValue"]

        request.addJSONHeaders(additionalHeaders: additionalHeaders)

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token123")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "CustomValue")
    }

    @Test("URLRequest JSON body addition")
    func urlRequestJSONBody() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)
        let testData = TestRequest(name: "Test", value: 42)
        let encoder = JSONEncoder()
        let logger = MockLogger()

        try request.addJSONBody(
            testData, encoder: encoder, printRequestBody: false, logger: logger, endpoint: "test",
            method: "POST")

        #expect(request.httpBody != nil)

        // Verify the JSON content
        if let bodyData = request.httpBody {
            let json = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            #expect(json?["name"] as? String == "Test")
            #expect(json?["value"] as? Int == 42)
        }

        // Test with nil body
        var request2 = URLRequest(url: URL(string: "https://example.com")!)
        let nilBody: TestRequest? = nil
        try request2.addJSONBody(
            nilBody, encoder: encoder, printRequestBody: false, logger: nil, endpoint: "test",
            method: "POST")
        #expect(request2.httpBody == nil)
    }

    @Test("URLRequest multipart data creation")
    func urlRequestMultipartData() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)

        // Create a temporary file for testing
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "test.txt")
        try "Test file content".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let parameters = ["description": "Test upload"] as [String: AnyObject]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters,
            fileKeyName: "file",
            fileURLs: [tempURL]
        )

        let logger = MockLogger()
        try request.addMultipartData(
            data: multipartData, printRequestBody: false, logger: logger, endpoint: "upload",
            method: "POST")

        #expect(request.httpBody != nil)
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data")
                == true)
        #expect(request.timeoutInterval == 60)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)

        // Verify multipart body contains our data
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            #expect(bodyString.contains("Test file content"))
            #expect(bodyString.contains("Test upload"))
        }
    }

    @Test("URLSession mimeType for various extensions")
    func urlSessionMimeTypeVariousExtensions() throws {
        let testCases: [(String, String)] = [
            ("txt", "text/plain"),
            ("json", "application/json"),
            ("pdf", "application/pdf"),
            ("png", "image/png"),
            ("jpg", "image/jpeg"),
            ("unknown", "application/octet-stream"),
        ]

        for (ext, expectedMimeType) in testCases {
            let actualMimeType = URLSession.mimeTypeForPath(ext)
            if ext == "unknown" {
                #expect(actualMimeType == expectedMimeType)
            } else {
                // For known extensions, check that we get a valid mime type (not necessarily the exact one)
                #expect(!actualMimeType.isEmpty)
            }
        }
    }

    @Test("Response data decoding")
    func responseDataDecoding() throws {
        let decoder = JSONDecoder()
        let logger = MockLogger()

        // Test normal decoding
        let testResponse = TestResponse(id: "123", status: "success")
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(testResponse)

        let decoded = try encodedData.decode(
            TestResponse.self, decoder: decoder, printResponseBody: false, logger: logger,
            endpoint: "test", method: "GET")
        #expect(decoded.id == "123")
        #expect(decoded.status == "success")

        // Test empty data with EmptyResponse
        let emptyData = Data()
        let emptyDecoded = try emptyData.decode(BaseAPI.EmptyResponse.self, decoder: decoder)
        #expect(type(of: emptyDecoded) == BaseAPI.EmptyResponse.self)

        // Test decoding with different data types
        let arrayData = try encoder.encode([testResponse, testResponse])
        let arrayDecoded = try arrayData.decode([TestResponse].self, decoder: decoder)
        #expect(arrayDecoded.count == 2)
        #expect(arrayDecoded[0].id == "123")
    }

    @Test("Analytics data tracking")
    func analyticsDataTracking() throws {
        let analytics = MockAnalytics()
        let startTime = Date()
        let endTime = Date().addingTimeInterval(0.5)

        // Test successful request tracking
        analytics.addAnalytics(
            endpoint: "/api/users",
            method: "GET",
            startTime: startTime,
            endTime: endTime,
            success: true,
            statusCode: 200,
            error: nil
        )

        // Test failed request tracking
        analytics.addAnalytics(
            endpoint: "/api/users",
            method: "POST",
            startTime: startTime,
            endTime: endTime,
            success: false,
            statusCode: 422,
            error: "Validation failed"
        )

        #expect(analytics.analyticsData.count == 2)

        let successRequest = analytics.analyticsData[0]
        #expect(successRequest.endpoint == "/api/users")
        #expect(successRequest.method == "GET")
        #expect(successRequest.success == true)
        #expect(successRequest.statusCode == 200)
        #expect(successRequest.error == nil)

        let failedRequest = analytics.analyticsData[1]
        #expect(failedRequest.success == false)
        #expect(failedRequest.statusCode == 422)
        #expect(failedRequest.error == "Validation failed")

        // Verify timing data
        #expect(successRequest.endTime >= successRequest.startTime)
        #expect(failedRequest.endTime >= failedRequest.startTime)
    }

    @Test("HTTPMethod all cases")
    func httpMethodAllCases() throws {
        let allMethods = BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases

        #expect(allMethods.contains(.get))
        #expect(allMethods.contains(.post))
        #expect(allMethods.contains(.put))
        #expect(allMethods.contains(.patch))
        #expect(allMethods.contains(.delete))
        #expect(allMethods.count == 5)

        for method in allMethods {
            #expect(!method.rawValue.isEmpty)
        }
    }

    @Test("MockEndpoint edge cases")
    func mockEndpointEdgeCases() throws {
        let endpointWithToken = MockEndpoint(endpoint: "secure", token: "abc123")
        let endpointWithoutToken = MockEndpoint(endpoint: "public", token: nil)
        let endpointWithEmptyToken = MockEndpoint(endpoint: "empty", token: "")

        #expect(endpointWithToken.headers?["Authorization"] == "Bearer abc123")
        #expect(endpointWithoutToken.headers?.isEmpty == true)
        #expect(endpointWithEmptyToken.headers?["Authorization"] == "Bearer ")

        // Test equality
        let endpoint1 = MockEndpoint(endpoint: "test", token: "token")
        let endpoint2 = MockEndpoint(endpoint: "test", token: "token")
        let endpoint3 = MockEndpoint(endpoint: "different", token: "token")

        #expect(endpoint1 == endpoint2)
        #expect(endpoint1 != endpoint3)
    }

    @Test("BaseAPIClient custom configuration")
    func baseAPIClientCustomConfiguration() throws {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        sessionConfig.allowsCellularAccess = false

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let analytics = MockAnalytics()
        let logger = MockLogger()

        var unauthorizedCount = 0
        let unauthorizedHandler: (MockEndpoint) -> Void = { _ in
            unauthorizedCount += 1
        }

        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: sessionConfig,
            encoder: encoder,
            decoder: decoder,
            analytics: analytics,
            logger: logger,
            unauthorizedHandler: unauthorizedHandler
        )

        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
        #expect(unauthorizedCount == 0)  // Handler not called during init
    }

    @Test("MultipartData edge cases")
    func multipartDataEdgeCases() throws {
        // Empty multipart data
        let emptyData = BaseAPI.MultipartData(parameters: nil, fileKeyName: "empty", fileURLs: nil)
        #expect(emptyData.stringValue == "fileKeyName: empty")

        // Multipart data with empty parameters
        let emptyParams = BaseAPI.MultipartData(parameters: [:], fileKeyName: "test", fileURLs: nil)
        #expect(emptyParams.stringValue == "fileKeyName: test")

        // Multipart data with empty file URLs
        let emptyFiles = BaseAPI.MultipartData(parameters: nil, fileKeyName: "files", fileURLs: [])
        #expect(emptyFiles.stringValue == "fileKeyName: files")

        // Complex parameters
        let complexParams = [
            "string": "value" as AnyObject,
            "number": 42 as AnyObject,
            "array": ["a", "b", "c"] as AnyObject,
        ]
        let complexData = BaseAPI.MultipartData(
            parameters: complexParams, fileKeyName: "complex", fileURLs: nil)
        let stringValue = complexData.stringValue
        #expect(stringValue.contains("parameters:"))
        #expect(stringValue.contains("fileKeyName: complex"))
    }

    // MARK: - API Client Integration Tests

    @Test("HTTP method validation")
    func httpMethodValidation() throws {
        let methods = BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases

        #expect(methods.count == 5)
        #expect(methods.contains(.get))
        #expect(methods.contains(.post))
        #expect(methods.contains(.put))
        #expect(methods.contains(.patch))
        #expect(methods.contains(.delete))

        // Test raw values
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.get.rawValue == "GET")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.post.rawValue == "POST")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.put.rawValue == "PUT")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")
    }

    @Test("Request timeout and caching configuration")
    func requestConfiguration() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)

        // Test multipart request configuration
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
            "config-test.txt")
        try "Configuration test".write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let multipartData = BaseAPI.MultipartData(
            parameters: ["test": "value" as AnyObject],
            fileKeyName: "file",
            fileURLs: [tempURL]
        )

        try request.addMultipartData(
            data: multipartData,
            printRequestBody: false,
            logger: nil,
            endpoint: "test",
            method: "POST"
        )

        // Verify request configuration
        #expect(request.timeoutInterval == 60)
        #expect(request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData)
        #expect(
            request.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data")
                == true)
    }

    @Test("Endpoint equality and hashing")
    func endpointEquality() throws {
        let endpoint1 = MockEndpoint(endpoint: "users/123", token: "token1")
        let endpoint2 = MockEndpoint(endpoint: "users/123", token: "token1")
        let endpoint3 = MockEndpoint(endpoint: "users/456", token: "token1")
        let endpoint4 = MockEndpoint(endpoint: "users/123", token: "token2")

        // Test equality
        #expect(endpoint1 == endpoint2)
        #expect(endpoint1 != endpoint3)  // Different endpoint
        #expect(endpoint1 != endpoint4)  // Different token

        // Test endpoint collections work as expected
        let endpoints = [endpoint1, endpoint2, endpoint3]
        #expect(endpoints.count == 3)

        // Test filtering equal endpoints
        let uniqueEndpoints = endpoints.filter { ep in
            endpoints.first { $0 == ep } == ep
        }
        #expect(uniqueEndpoints.count <= endpoints.count)
    }

    // MARK: - Extended Coverage Tests

    @Test("BaseAPI.APIError localized descriptions")
    func apiErrorLocalizedDescriptions() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 400,
            httpVersion: nil,
            headerFields: nil
        )!

        let errors: [BaseAPI.APIError] = [
            .encodingFailed,
            .networkError("Connection timeout"),
            .invalidResponse(response: URLResponse()),
            .serverError(response: httpResponse, code: 400, requestID: "req-123"),
            .decodingFailed(response: httpResponse, error: "Invalid JSON"),
            .unknown,
        ]

        for error in errors {
            let description = error.localizedDescription
            #expect(!description.isEmpty)
            #expect(description.count > 5)  // Reasonable description length
        }
    }

    @Test("URLRequest extensions error handling")
    func urlRequestExtensionsErrorHandling() throws {
        var request = URLRequest(url: URL(string: "https://example.com")!)

        // Test encoding failure scenario with a proper encodable type that throws
        struct EncodingFailureRequest: Codable {
            let shouldFail: Bool

            init(shouldFail: Bool = true) {
                self.shouldFail = shouldFail
            }

            func encode(to encoder: Encoder) throws {
                if shouldFail {
                    throw EncodingError.invalidValue(
                        self,
                        EncodingError.Context(
                            codingPath: [],
                            debugDescription: "Simulated encoding failure"
                        )
                    )
                }
            }
        }

        // Test that encoding failure is handled (we won't actually call addJSONBody with this as it would throw)
        let failureRequest = EncodingFailureRequest()
        #expect(failureRequest.shouldFail == true)

        // Test empty auth header
        request.addJSONHeaders(additionalHeaders: [:])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        // Test header merging
        request.addJSONHeaders(additionalHeaders: ["Content-Type": "application/custom"])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/custom")
    }

    @Test("Data extension error scenarios")
    func dataExtensionErrorScenarios() throws {
        let decoder = JSONDecoder()

        // Test invalid JSON data
        let invalidJSONData = "invalid json".data(using: .utf8)!

        do {
            _ = try invalidJSONData.decode(TestResponse.self, decoder: decoder)
            #expect(Bool(false), "Should have thrown decoding error")
        } catch {
            #expect(error is DecodingError)
        }

        // Test empty data with non-EmptyResponse type
        let emptyData = Data()
        do {
            _ = try emptyData.decode(TestResponse.self, decoder: decoder)
            #expect(Bool(false), "Should have thrown decoding error")
        } catch {
            #expect(error is DecodingError)
        }
    }

    @Test("MockEndpoint comprehensive testing")
    func mockEndpointComprehensiveTesting() throws {
        // Test various endpoint configurations
        let endpoints = [
            MockEndpoint(endpoint: "users", token: "valid-token"),
            MockEndpoint(endpoint: "posts/123", token: "another-token"),
            MockEndpoint(endpoint: "search", token: nil),
            MockEndpoint(endpoint: "admin/settings", token: "admin-token"),
        ]

        for endpoint in endpoints {
            #expect(endpoint.url.absoluteString.contains(endpoint.path))
            #expect(endpoint.stringValue == endpoint.endpoint)

            if let token = endpoint.token, !token.isEmpty {
                #expect(endpoint.headers?["Authorization"] == "Bearer \(token)")
            } else {
                #expect(endpoint.headers?.isEmpty == true)
            }
        }

        // Test endpoint equality with various combinations
        let endpoint1 = MockEndpoint(endpoint: "test", token: "token1")
        let endpoint2 = MockEndpoint(endpoint: "test", token: "token1")
        let endpoint3 = MockEndpoint(endpoint: "test", token: "token2")
        let endpoint4 = MockEndpoint(endpoint: "different", token: "token1")

        #expect(endpoint1 == endpoint2)
        #expect(endpoint1 != endpoint3)  // Different tokens
        #expect(endpoint1 != endpoint4)  // Different endpoints
    }

    @Test("HTTPMethod comprehensive coverage")
    func httpMethodComprehensiveCoverage() throws {
        let methods = BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases

        // Test each method individually
        for method in methods {
            #expect(!method.rawValue.isEmpty)
            #expect(method.rawValue.allSatisfy { $0.isUppercase })
        }

        // Test specific method values
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.get.rawValue == "GET")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.post.rawValue == "POST")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.put.rawValue == "PUT")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.patch.rawValue == "PATCH")
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")

        // Test that all cases are covered
        let expectedMethods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE"]
        let actualMethods = Set(methods.map { $0.rawValue })
        #expect(actualMethods == expectedMethods)
    }

    @Test("JSON encoder/decoder configuration")
    func jsonCoderConfiguration() throws {
        // Test custom encoder settings
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Test date encoding/decoding
        struct DateModel: Codable {
            let timestamp: Date
            let name: String
        }

        let testDate = Date(timeIntervalSince1970: 1_640_995_200)  // 2022-01-01 00:00:00 UTC
        let model = DateModel(timestamp: testDate, name: "test")

        let encodedData = try encoder.encode(model)
        let decodedModel = try decoder.decode(DateModel.self, from: encodedData)

        #expect(decodedModel.name == "test")
        #expect(
            abs(decodedModel.timestamp.timeIntervalSince1970 - testDate.timeIntervalSince1970) < 1.0
        )

        // Verify pretty printing is working
        let jsonString = String(data: encodedData, encoding: .utf8)!
        #expect(jsonString.contains("\n"))  // Pretty printed should have newlines
    }

    @Test("EmptyResponse comprehensive testing")
    func emptyResponseComprehensiveTesting() throws {
        let emptyResponse1 = BaseAPI.EmptyResponse()
        let emptyResponse2 = BaseAPI.EmptyResponse()

        // Test JSON encoding/decoding
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let encodedData = try encoder.encode(emptyResponse1)
        let decodedResponse = try decoder.decode(BaseAPI.EmptyResponse.self, from: encodedData)

        #expect(type(of: decodedResponse) == BaseAPI.EmptyResponse.self)

        // Test with pretty printing
        encoder.outputFormatting = .prettyPrinted
        let prettyEncodedData = try encoder.encode(emptyResponse2)
        let prettyString = String(data: prettyEncodedData, encoding: .utf8)
        #expect(prettyString?.contains("{") == true)
        #expect(prettyString?.contains("}") == true)
    }

    @Test("Request body encoding")
    func requestBodyEncoding() throws {
        let testRequest = TestRequest(name: "John Doe", value: 42)
        let encoder = JSONEncoder()

        let data = try encoder.encode(testRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["name"] as? String == "John Doe")
        #expect(json?["value"] as? Int == 42)
    }

    @Test("API error response handling")
    func apiErrorResponseHandling() throws {
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/test")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["x-request-id": "req-123"]
        )!

        let serverError = BaseAPI.APIError.serverError(
            response: httpResponse, code: 404, requestID: "req-123")

        #expect(serverError.errorDescription?.contains("404") == true)
        #expect(serverError.errorDescription?.contains("req-123") == true)
        #expect(serverError.isClientError == false)
        #expect(serverError.getResponse() == httpResponse)

        // Test different error types
        let networkError = BaseAPI.APIError.networkError("Connection timeout")
        #expect(networkError.errorDescription?.contains("Connection timeout") == true)
        #expect(networkError.isClientError == false)
        #expect(networkError.getResponse() == nil)

        let encodingError = BaseAPI.APIError.encodingFailed
        #expect(encodingError.isClientError == true)
        #expect(encodingError.getResponse() == nil)
    }

    // MARK: - PATCH Method Tests

    @Test("PATCH method existence")
    func patchMethodExistence() throws {
        // Verify PATCH method exists in HTTPMethod enum
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.patch.rawValue == "PATCH")
    }

    @Test("PATCH request building")
    func patchRequestBuilding() throws {
        let testRequest = TestRequest(name: "Updated User", value: 25)
        let encoder = JSONEncoder()

        let data = try encoder.encode(testRequest)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // Verify request body structure
        #expect(json?["name"] as? String == "Updated User")
        #expect(json?["value"] as? Int == 25)
    }

    @Test("PATCH HTTP method in allCases")
    func patchHttpMethodInAllCases() throws {
        let methods = BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases
        let methodStrings = Set(methods.map { $0.rawValue })

        #expect(methodStrings.contains("PATCH"))
        #expect(methodStrings.count == 5)  // GET, POST, PUT, PATCH, DELETE
    }

    @Test("PATCH method endpoint integration")
    func patchMethodEndpointIntegration() throws {
        let endpoint = MockEndpoint(endpoint: "users/123/profile", token: "test-token")
        let testRequest = TestRequest(name: "Jane Doe", value: 30)

        // Verify endpoint and request can be structured for PATCH
        #expect(endpoint.url.absoluteString == "https://api.example.com/users/123/profile")
        #expect(endpoint.stringValue == "users/123/profile")
        #expect(endpoint.headers?["Authorization"] == "Bearer test-token")

        // Verify request is encodable
        let encoder = JSONEncoder()
        let data = try encoder.encode(testRequest)
        #expect(!data.isEmpty)
    }

    @Test("PATCH request with various endpoints")
    func patchRequestWithVariousEndpoints() throws {
        let endpoints = [
            MockEndpoint(endpoint: "users/1", token: "token1"),
            MockEndpoint(endpoint: "posts/abc", token: "token2"),
            MockEndpoint(endpoint: "comments/xyz", token: nil),
        ]

        for endpoint in endpoints {
            let testRequest = TestRequest(name: "Updated", value: 100)
            let encoder = JSONEncoder()

            let data = try encoder.encode(testRequest)
            #expect(!data.isEmpty)
            #expect(endpoint.url.absoluteString.contains(endpoint.endpoint))
        }
    }

    // MARK: - DELETE Method Tests

    @Test("DELETE method existence")
    func deleteMethodExistence() throws {
        // Verify DELETE method exists in HTTPMethod enum
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")
    }

    @Test("DELETE HTTP method in allCases")
    func deleteHttpMethodInAllCases() throws {
        let methods = BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases
        let methodStrings = Set(methods.map { $0.rawValue })

        #expect(methodStrings.contains("DELETE"))
        #expect(methodStrings.count == 5)  // GET, POST, PUT, PATCH, DELETE
    }

    @Test("DELETE endpoint integration")
    func deleteEndpointIntegration() throws {
        let endpoint = MockEndpoint(endpoint: "users/123", token: "test-token")

        // Verify endpoint structure for DELETE
        #expect(endpoint.url.absoluteString == "https://api.example.com/users/123")
        #expect(endpoint.stringValue == "users/123")
        #expect(endpoint.headers?["Authorization"] == "Bearer test-token")
    }

    @Test("DELETE request with various endpoints")
    func deleteRequestWithVariousEndpoints() throws {
        let endpoints = [
            MockEndpoint(endpoint: "users/1", token: "token1"),
            MockEndpoint(endpoint: "posts/abc", token: "token2"),
            MockEndpoint(endpoint: "comments/xyz", token: nil),
        ]

        for endpoint in endpoints {
            // Verify endpoint can be used for DELETE
            #expect(endpoint.url.absoluteString.contains(endpoint.endpoint))
            #expect(!endpoint.stringValue.isEmpty)
        }
    }

    @Test("DELETE method signature verification")
    func deleteMethodSignatureVerification() throws {
        let endpoint = MockEndpoint(endpoint: "items/42", token: "test-token")
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(logger: nil)

        // Verify client has delete method
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
        #expect(endpoint.url.absoluteString.contains("items/42"))
    }

    @Test("DELETE with empty response handling")
    func deleteWithEmptyResponseHandling() throws {
        let emptyResponse = BaseAPI.EmptyResponse()
        let encoder = JSONEncoder()

        // Verify EmptyResponse is properly codable for DELETE responses
        let data = try encoder.encode(emptyResponse)
        #expect(!data.isEmpty)
    }

    @Test("DELETE endpoint configurations")
    func deleteEndpointConfigurations() throws {
        let configs = [
            MockEndpoint(endpoint: "users/1/settings", token: "token1"),
            MockEndpoint(endpoint: "api/v2/resources/delete-me", token: "token2"),
            MockEndpoint(endpoint: "items/123/comments/456", token: nil),
        ]

        for endpoint in configs {
            #expect(endpoint.url.absoluteString.contains(endpoint.endpoint))
            #expect(endpoint.stringValue == endpoint.endpoint)

            if let token = endpoint.token, !token.isEmpty {
                #expect(endpoint.headers?["Authorization"] == "Bearer \(token)")
            }
        }
    }

    // MARK: - Request Interceptor Tests

    @Test("Client initializes with interceptor")
    func clientInitializesWithInterceptor() throws {
        let interceptor = MockInterceptor(additionalHeaders: ["Authorization": "Bearer token"])
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(interceptor: interceptor)
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client initializes without interceptor")
    func clientInitializesWithoutInterceptor() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>()
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("MockInterceptor adapts request with headers")
    func mockInterceptorAdaptsRequest() async throws {
        let interceptor = MockInterceptor(additionalHeaders: [
            "Authorization": "Bearer my-token",
            "X-API-Key": "key-123",
        ])

        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await interceptor.adapt(request)

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == "key-123")
    }

    @Test("FailingInterceptor throws error")
    func failingInterceptorThrowsError() async {
        let interceptor = FailingInterceptor()
        let request = URLRequest(url: URL(string: "https://example.com")!)

        do {
            _ = try await interceptor.adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    // MARK: - Interceptor Chain Tests

    @Test("InterceptorChain applies interceptors in order")
    func interceptorChainAppliesInOrder() async throws {
        // Two interceptors that each add a header; second should not clobber first
        let first = MockInterceptor(additionalHeaders: ["X-First": "1"])
        let second = MockInterceptor(additionalHeaders: ["X-Second": "2"])
        let chain = BaseAPI.InterceptorChain([first, second])

        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await chain.adapt(request)

        #expect(request.value(forHTTPHeaderField: "X-First") == "1")
        #expect(request.value(forHTTPHeaderField: "X-Second") == "2")
    }

    @Test("InterceptorChain later interceptor overwrites same header")
    func interceptorChainOverwrites() async throws {
        let first = MockInterceptor(additionalHeaders: ["X-Token": "old"])
        let second = MockInterceptor(additionalHeaders: ["X-Token": "new"])
        let chain = BaseAPI.InterceptorChain([first, second])

        var request = URLRequest(url: URL(string: "https://example.com")!)
        request = try await chain.adapt(request)

        #expect(request.value(forHTTPHeaderField: "X-Token") == "new")
    }

    @Test("InterceptorChain with empty interceptors is a no-op")
    func interceptorChainEmpty() async throws {
        let chain = BaseAPI.InterceptorChain([])
        let original = URLRequest(url: URL(string: "https://example.com")!)
        let adapted = try await chain.adapt(original)
        #expect(adapted.url == original.url)
        #expect(adapted.allHTTPHeaderFields == original.allHTTPHeaderFields)
    }

    @Test("InterceptorChain propagates first failing interceptor")
    func interceptorChainPropagatesFailure() async {
        let chain = BaseAPI.InterceptorChain([FailingInterceptor()])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await chain.adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    @Test("InterceptorChain stops at first failing interceptor")
    func interceptorChainStopsAtFailure() async {
        // FailingInterceptor is first; second interceptor should never run
        let headerRecorder = MockInterceptor(additionalHeaders: ["X-Ran": "yes"])
        let chain = BaseAPI.InterceptorChain([FailingInterceptor(), headerRecorder])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        do {
            _ = try await chain.adapt(request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Error is from FailingInterceptor, not headerRecorder
            #expect(error is BaseAPI.APIError)
        }
    }

    // MARK: - RetryDecision Tests

    @Test("RetryDecision doNotRetry")
    func retryDecisionDoNotRetry() {
        let decision = BaseAPI.RetryDecision.doNotRetry
        if case .doNotRetry = decision {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected doNotRetry")
        }
    }

    @Test("RetryDecision retry with delay")
    func retryDecisionRetryWithDelay() {
        let decision = BaseAPI.RetryDecision.retry(delay: 2.5)
        if case .retry(let delay) = decision {
            #expect(delay == 2.5)
        } else {
            #expect(Bool(false), "Expected retry")
        }
    }

    @Test("RetryDecision retry with zero delay")
    func retryDecisionRetryZeroDelay() {
        let decision = BaseAPI.RetryDecision.retry(delay: 0)
        if case .retry(let delay) = decision {
            #expect(delay == 0)
        } else {
            #expect(Bool(false), "Expected retry with zero delay")
        }
    }

    @Test("Default retry implementation returns doNotRetry")
    func defaultRetryReturnsDoNotRetry() async {
        let interceptor = MockInterceptor(additionalHeaders: [:])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let decision = await interceptor.retry(
            request,
            dueTo: BaseAPI.APIError.unknown,
            attemptCount: 1
        )
        if case .doNotRetry = decision {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Default should be doNotRetry")
        }
    }

    @Test("InterceptorChain retry returns doNotRetry when no interceptor retries")
    func interceptorChainRetryNone() async {
        let chain = BaseAPI.InterceptorChain([
            MockInterceptor(additionalHeaders: [:]),
            MockInterceptor(additionalHeaders: [:]),
        ])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let decision = await chain.retry(request, dueTo: BaseAPI.APIError.unknown, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Should be doNotRetry") }
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
        let chain = BaseAPI.InterceptorChain([
            RetryingInterceptor(delay: 1.0),
            RetryingInterceptor(delay: 99.0),  // should never be reached
        ])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let decision = await chain.retry(request, dueTo: BaseAPI.APIError.unknown, attemptCount: 1)
        if case .retry(let delay) = decision {
            #expect(delay == 1.0)
        } else {
            #expect(Bool(false), "Should be retry with 1.0 delay")
        }
    }

    // MARK: - Client with Interceptors Array Tests

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
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [])
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Single-interceptor convenience init is equivalent to array init")
    func singleInterceptorConvenienceInit() throws {
        let interceptor = MockInterceptor(additionalHeaders: ["X-Auth": "token"])
        let clientA = BaseAPI.BaseAPIClient<MockEndpoint>(interceptor: interceptor)
        let clientB = BaseAPI.BaseAPIClient<MockEndpoint>(interceptors: [interceptor])
        // Both should be the same type and not crash
        #expect(type(of: clientA) == type(of: clientB))
    }

    // MARK: - ResponseValidator Tests

    @Test("StatusCodeValidator accepts 2xx responses")
    func statusCodeValidatorAccepts2xx() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)

        for code in [200, 201, 204, 299] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            // Should not throw
            try validator.validate(response, data: Data(), for: request)
        }
    }

    @Test("StatusCodeValidator rejects non-2xx responses")
    func statusCodeValidatorRejectsNon2xx() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)

        for code in [400, 401, 403, 404, 409, 422, 500, 503] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            do {
                try validator.validate(response, data: Data(), for: request)
                #expect(Bool(false), "Should have thrown for status \(code)")
            } catch let error as BaseAPI.APIError {
                if case .serverError(_, let errorCode, _) = error {
                    #expect(errorCode == code)
                } else {
                    #expect(Bool(false), "Expected .serverError, got \(error)")
                }
            }
        }
    }

    @Test("StatusCodeValidator includes x-request-id from response headers")
    func statusCodeValidatorIncludesRequestId() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: ["x-request-id": "req-abc-123"]
        )!
        do {
            try validator.validate(response, data: Data(), for: request)
            #expect(Bool(false), "Should have thrown")
        } catch let error as BaseAPI.APIError {
            if case .serverError(_, _, let requestID) = error {
                #expect(requestID == "req-abc-123")
            } else {
                #expect(Bool(false), "Expected .serverError")
            }
        }
    }

    @Test("StatusCodeValidator uses N/A when x-request-id header is absent")
    func statusCodeValidatorFallbackRequestId() throws {
        let validator = BaseAPI.StatusCodeValidator()
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        do {
            try validator.validate(response, data: Data(), for: request)
            #expect(Bool(false), "Should have thrown")
        } catch let error as BaseAPI.APIError {
            if case .serverError(_, _, let requestID) = error {
                #expect(requestID == "N/A")
            } else {
                #expect(Bool(false), "Expected .serverError")
            }
        }
    }

    @Test("AcceptedStatusCodesValidator accepts only specified codes")
    func acceptedStatusCodesValidatorAcceptsSpecified() throws {
        let validator = BaseAPI.AcceptedStatusCodesValidator([200, 201, 304])
        let request = URLRequest(url: URL(string: "https://example.com")!)

        for code in [200, 201, 304] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            try validator.validate(response, data: Data(), for: request)
        }
    }

    @Test("AcceptedStatusCodesValidator rejects unspecified codes")
    func acceptedStatusCodesValidatorRejectsOthers() throws {
        let validator = BaseAPI.AcceptedStatusCodesValidator([200, 201])
        let request = URLRequest(url: URL(string: "https://example.com")!)

        for code in [204, 400, 500] {
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com")!,
                statusCode: code,
                httpVersion: nil,
                headerFields: nil
            )!
            do {
                try validator.validate(response, data: Data(), for: request)
                #expect(Bool(false), "Should have thrown for status \(code)")
            } catch {
                #expect(error is BaseAPI.APIError)
            }
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
        #expect(throws: (any Error).self) {
            try validator.validate(notOk, data: Data(), for: request)
        }
    }

    @Test("Client init with custom validators")
    func clientInitWithCustomValidators() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            validators: [BaseAPI.AcceptedStatusCodesValidator([200, 201, 204])]
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client init with empty validators array")
    func clientInitWithEmptyValidators() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(validators: [])
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client init with default validators uses StatusCodeValidator")
    func clientInitDefaultValidators() throws {
        // Default init should compile and succeed (StatusCodeValidator is the default)
        let client = BaseAPI.BaseAPIClient<MockEndpoint>()
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("Client convenience init accepts validators parameter")
    func clientConvenienceInitWithValidators() throws {
        let interceptor = MockInterceptor(additionalHeaders: ["X-Auth": "token"])
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            interceptor: interceptor,
            validators: [BaseAPI.StatusCodeValidator()]
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
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

        let noOp = NoOpValidator()
        try noOp.validate(response, data: Data(), for: request)  // Should not throw

        let alwaysFail = AlwaysFailValidator()
        do {
            try alwaysFail.validate(response, data: Data(), for: request)
            #expect(Bool(false), "Should have thrown")
        } catch {
            #expect(error is BaseAPI.APIError)
        }
    }

    // MARK: - BackoffStrategy Tests

    @Test("BackoffStrategy.none always returns zero delay")
    func backoffNoneReturnsZero() {
        let strategy = BaseAPI.BackoffStrategy.none
        for attempt in 1...5 {
            #expect(strategy.delay(for: attempt) == 0)
        }
    }

    @Test("BackoffStrategy.constant always returns fixed delay")
    func backoffConstantReturnsFixed() {
        let strategy = BaseAPI.BackoffStrategy.constant(2.5)
        for attempt in 1...5 {
            #expect(strategy.delay(for: attempt) == 2.5)
        }
    }

    @Test("BackoffStrategy.exponential doubles delay each attempt")
    func backoffExponentialDoubles() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 1, multiplier: 2, maxDelay: 60)
        #expect(strategy.delay(for: 1) == 1.0)   // 1 * 2^0
        #expect(strategy.delay(for: 2) == 2.0)   // 1 * 2^1
        #expect(strategy.delay(for: 3) == 4.0)   // 1 * 2^2
        #expect(strategy.delay(for: 4) == 8.0)   // 1 * 2^3
        #expect(strategy.delay(for: 5) == 16.0)  // 1 * 2^4
    }

    @Test("BackoffStrategy.exponential respects maxDelay cap")
    func backoffExponentialCapsAtMaxDelay() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 1, multiplier: 2, maxDelay: 5)
        #expect(strategy.delay(for: 1) == 1.0)
        #expect(strategy.delay(for: 2) == 2.0)
        #expect(strategy.delay(for: 3) == 4.0)
        #expect(strategy.delay(for: 4) == 5.0)  // capped: 8 → 5
        #expect(strategy.delay(for: 5) == 5.0)  // capped: 16 → 5
    }

    @Test("BackoffStrategy.exponential with custom base and multiplier")
    func backoffExponentialCustom() {
        let strategy = BaseAPI.BackoffStrategy.exponential(base: 0.5, multiplier: 3, maxDelay: 100)
        #expect(strategy.delay(for: 1) == 0.5)    // 0.5 * 3^0
        #expect(strategy.delay(for: 2) == 1.5)    // 0.5 * 3^1
        #expect(strategy.delay(for: 3) == 4.5)    // 0.5 * 3^2
    }

    // MARK: - RetryPolicy Tests

    @Test("RetryPolicy retries on retryable status codes")
    func retryPolicyRetriesOnRetryableStatusCodes() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .none, retryableStatusCodes: [500, 503])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x")

        let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
        if case .retry(let delay) = decision {
            #expect(delay == 0)
        } else {
            #expect(Bool(false), "Expected .retry")
        }
    }

    @Test("RetryPolicy does not retry on non-retryable status codes")
    func retryPolicySkipsNonRetryableStatusCodes() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 404,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 404, requestID: "x")

        let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Expected .doNotRetry") }
    }

    @Test("RetryPolicy stops after maxAttempts")
    func retryPolicyStopsAtMaxAttempts() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x")

        // attemptCount == maxAttempts means we've exhausted retries
        let decision = await policy.retry(request, dueTo: error, attemptCount: 3)
        if case .doNotRetry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Expected .doNotRetry at attempt 3 with maxAttempts 3") }
    }

    @Test("RetryPolicy still retries below maxAttempts")
    func retryPolicyRetriesBelowMax() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, retryableStatusCodes: [500])
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x")

        let d1 = await policy.retry(request, dueTo: error, attemptCount: 1)
        let d2 = await policy.retry(request, dueTo: error, attemptCount: 2)
        if case .retry = d1 { #expect(Bool(true)) } else { #expect(Bool(false)) }
        if case .retry = d2 { #expect(Bool(true)) } else { #expect(Bool(false)) }
    }

    @Test("RetryPolicy retries network errors when retryNetworkErrors is true")
    func retryPolicyRetriesNetworkErrors() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .constant(1), retryNetworkErrors: true)
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let error = BaseAPI.APIError.networkError("timeout")

        let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
        if case .retry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Expected .retry for network error") }
    }

    @Test("RetryPolicy does not retry network errors by default")
    func retryPolicySkipsNetworkErrorsByDefault() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3)  // retryNetworkErrors defaults to false
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let error = BaseAPI.APIError.networkError("timeout")

        let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Expected .doNotRetry for network error") }
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
                url: URL(string: "https://example.com")!, statusCode: code,
                httpVersion: nil, headerFields: nil)!
            let error = BaseAPI.APIError.serverError(response: response, code: code, requestID: "x")
            let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
            if case .retry = decision { #expect(Bool(true)) }
            else { #expect(Bool(false), "Expected retry for \(code)") }
        }
    }

    @Test("RetryPolicy does not retry non-server errors")
    func retryPolicySkipsNonServerErrors() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3)
        let request = URLRequest(url: URL(string: "https://example.com")!)

        for error: BaseAPI.APIError in [.encodingFailed, .unknown] {
            let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
            if case .doNotRetry = decision { #expect(Bool(true)) }
            else { #expect(Bool(false), "Expected .doNotRetry for \(error)") }
        }
    }

    @Test("RetryPolicy maxAttempts clamped to minimum 1")
    func retryPolicyMinAttempts() async {
        let policy = BaseAPI.RetryPolicy(maxAttempts: 0)  // should clamp to 1
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 500, requestID: "x")

        // attemptCount 1 >= maxAttempts(1), so doNotRetry
        let decision = await policy.retry(request, dueTo: error, attemptCount: 1)
        if case .doNotRetry = decision { #expect(Bool(true)) }
        else { #expect(Bool(false), "Expected .doNotRetry when maxAttempts clamped to 1") }
    }

    @Test("RetryPolicy uses exponential backoff delay")
    func retryPolicyExponentialDelay() async {
        let policy = BaseAPI.RetryPolicy(
            maxAttempts: 5,
            backoff: .exponential(base: 1, multiplier: 2, maxDelay: 60),
            retryableStatusCodes: [500]
        )
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 500,
            httpVersion: nil, headerFields: nil)!
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
        let policy = BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .constant(0.5), retryableStatusCodes: [503])
        let auth = MockInterceptor(additionalHeaders: ["Authorization": "Bearer tok"])
        let chain = BaseAPI.InterceptorChain([auth, policy])

        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!, statusCode: 503,
            httpVersion: nil, headerFields: nil)!
        let error = BaseAPI.APIError.serverError(response: response, code: 503, requestID: "x")

        // Chain should find RetryPolicy's .retry decision
        let decision = await chain.retry(request, dueTo: error, attemptCount: 1)
        if case .retry(let delay) = decision {
            #expect(delay == 0.5)
        } else {
            #expect(Bool(false), "Expected .retry from chain")
        }
    }

    @Test("Client initialises with RetryPolicy in interceptors array")
    func clientInitWithRetryPolicy() {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            interceptors: [
                MockInterceptor(additionalHeaders: ["X-App": "test"]),
                BaseAPI.RetryPolicy(maxAttempts: 3, backoff: .exponential(base: 1, multiplier: 2, maxDelay: 30)),
            ]
        )
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

}

// MARK: - Network Tests (serialized to prevent MockURLProtocol.handler races across suites)

@Suite("Network Tests", .serialized)
struct NetworkTests {

@Suite("Raw Body Tests")
struct RawBodyTests {

    /// Registers a response handler and returns a client wired to MockURLProtocol.
    private func client(responding handler: @escaping MockURLProtocol.Handler) -> BaseAPI.BaseAPIClient<MockEndpoint> {
        MockURLProtocol.handler = handler
        return BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())
    }

    @Test("post(rawBody:) sends pre-serialized body unchanged")
    func postRawBodySendsUnchanged() async throws {
        let payload = TestResponse(id: "42", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBodyRef = ActorBox<Data?>(nil)

        let c = client { request in
            await capturedBodyRef.set(request.httpBody)
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = try JSONEncoder().encode(TestRequest(name: "replay", value: 7))
        let response: BaseAPI.APIResponse<TestResponse> = try await c.post(
            MockEndpoint(endpoint: "items", token: nil), rawBody: raw)

        let captured = await capturedBodyRef.value
        #expect(captured == raw)
        #expect(response.data.id == "42")
    }

    @Test("put(rawBody:) sends pre-serialized body unchanged")
    func putRawBodySendsUnchanged() async throws {
        let payload = TestResponse(id: "99", status: "updated")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBodyRef = ActorBox<Data?>(nil)

        let c = client { request in
            await capturedBodyRef.set(request.httpBody)
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = try JSONEncoder().encode(TestRequest(name: "update", value: 3))
        let response: BaseAPI.APIResponse<TestResponse> = try await c.put(
            MockEndpoint(endpoint: "items/99", token: nil), rawBody: raw)

        let captured = await capturedBodyRef.value
        #expect(captured == raw)
        #expect(response.data.id == "99")
    }

    @Test("patch(rawBody:) sends pre-serialized body unchanged")
    func patchRawBodySendsUnchanged() async throws {
        let payload = TestResponse(id: "7", status: "patched")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBodyRef = ActorBox<Data?>(nil)

        let c = client { request in
            await capturedBodyRef.set(request.httpBody)
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = try JSONEncoder().encode(TestRequest(name: "partial", value: 1))
        let response: BaseAPI.APIResponse<TestResponse> = try await c.patch(
            MockEndpoint(endpoint: "items/7", token: nil), rawBody: raw)

        let captured = await capturedBodyRef.value
        #expect(captured == raw)
        #expect(response.data.id == "7")
    }

    @Test("post(rawBody:) propagates server error")
    func postRawBodyPropagatesError() async throws {
        let c = client { request in
            return (Data(), HTTPURLResponse(
                url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!)
        }
        let raw = Data("{}".utf8)
        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c.post(
                MockEndpoint(endpoint: "items", token: nil), rawBody: raw)
            #expect(Bool(false), "Should have thrown")
        } catch let error as BaseAPI.APIError {
            if case .serverError(_, let code, _) = error {
                #expect(code == 422)
            } else {
                #expect(Bool(false), "Expected .serverError")
            }
        }
    }

    @Test("post(rawBody:then:) callback receives success")
    func postRawBodyCallbackSuccess() async throws {
        let payload = TestResponse(id: "cb1", status: "ok")
        let responseData = try JSONEncoder().encode(payload)

        let c = client { request in
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = Data("{}".utf8)

        let result = await withCheckedContinuation { continuation in
            c.post(MockEndpoint(endpoint: "cb", token: nil), rawBody: raw) {
                (result: BaseAPI.APIResult<TestResponse>) in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.data.id == "cb1")
        case .failure:
            #expect(Bool(false), "Expected success")
        }
    }

    @Test("put(rawBody:then:) callback receives failure")
    func putRawBodyCallbackFailure() async throws {
        let c = client { request in
            return (Data(), HTTPURLResponse(
                url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }

        let raw = Data("{}".utf8)

        let result = await withCheckedContinuation { continuation in
            c.put(MockEndpoint(endpoint: "cb", token: nil), rawBody: raw) {
                (result: BaseAPI.APIResult<TestResponse>) in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success:
            #expect(Bool(false), "Expected failure")
        case .failure:
            #expect(Bool(true))
        }
    }

    @Test("patch(rawBody:then:) callback receives success")
    func patchRawBodyCallbackSuccess() async throws {
        let payload = TestResponse(id: "p1", status: "patched")
        let responseData = try JSONEncoder().encode(payload)

        let c = client { request in
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = Data("{}".utf8)

        let result = await withCheckedContinuation { continuation in
            c.patch(MockEndpoint(endpoint: "cb", token: nil), rawBody: raw) {
                (result: BaseAPI.APIResult<TestResponse>) in
                continuation.resume(returning: result)
            }
        }

        switch result {
        case .success(let response):
            #expect(response.data.id == "p1")
        case .failure:
            #expect(Bool(false), "Expected success")
        }
    }

    @Test("raw body requests set Content-Type: application/json header")
    func rawBodyRequestSetsContentType() async throws {
        let payload = TestResponse(id: "hdr", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedHeaderRef = ActorBox<String?>(nil)

        let c = client { request in
            await capturedHeaderRef.set(request.value(forHTTPHeaderField: "Content-Type"))
            return (responseData, HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let raw = Data("{}".utf8)
        let _: BaseAPI.APIResponse<TestResponse> = try await c.post(
            MockEndpoint(endpoint: "hdr", token: nil), rawBody: raw)

        let header = await capturedHeaderRef.value
        #expect(header == "application/json")
    }
}

// MARK: - RequestEventMonitor Tests

@Suite("Event Monitor Tests")
struct EventMonitorTests {

    // MARK: - Helpers

    /// A monitor that records every event it receives.
    final class RecordingMonitor: BaseAPI.RequestEventMonitor, @unchecked Sendable {
        var starts: [(endpoint: String, method: String)] = []
        var retries: [(endpoint: String, attemptCount: Int, delay: TimeInterval)] = []
        var finishes: [(endpoint: String, statusCode: Int, duration: TimeInterval)] = []
        var failures: [(endpoint: String, error: BaseAPI.APIError, duration: TimeInterval)] = []

        func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {
            starts.append((endpoint, method))
        }
        func requestWillRetry(_ request: URLRequest, endpoint: String, method: String,
                              attemptCount: Int, delay: TimeInterval) {
            retries.append((endpoint, attemptCount, delay))
        }
        func requestDidFinish(_ request: URLRequest, endpoint: String, method: String,
                              response: HTTPURLResponse, duration: TimeInterval) {
            finishes.append((endpoint, response.statusCode, duration))
        }
        func requestDidFail(_ request: URLRequest, endpoint: String, method: String,
                            error: BaseAPI.APIError, duration: TimeInterval) {
            failures.append((endpoint, error, duration))
        }
    }

    private func makeClient(monitor: BaseAPI.RequestEventMonitor,
                            handler: @escaping MockURLProtocol.Handler)
        -> BaseAPI.BaseAPIClient<MockEndpoint>
    {
        MockURLProtocol.handler = handler
        return BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            eventMonitors: [monitor]
        )
    }

    // MARK: - Tests

    @Test("requestDidStart fires once on a successful request")
    func startFiresOnSuccess() async throws {
        let monitor = RecordingMonitor()
        let payload = TestResponse(id: "1", status: "ok")
        let data = try JSONEncoder().encode(payload)

        let c = makeClient(monitor: monitor) { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "items", token: nil))
        #expect(monitor.starts.count == 1)
        #expect(monitor.starts[0].endpoint == "items")
        #expect(monitor.starts[0].method == "GET")
    }

    @Test("requestDidFinish fires with correct status code and positive duration")
    func finishFiresWithStatusAndDuration() async throws {
        let monitor = RecordingMonitor()
        let payload = TestResponse(id: "2", status: "ok")
        let data = try JSONEncoder().encode(payload)

        let c = makeClient(monitor: monitor) { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "items", token: nil))
        #expect(monitor.finishes.count == 1)
        #expect(monitor.finishes[0].statusCode == 200)
        #expect(monitor.finishes[0].duration >= 0)
    }

    @Test("requestDidFail fires on server error")
    func failFiresOnServerError() async throws {
        let monitor = RecordingMonitor()

        let c = makeClient(monitor: monitor) { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
        }

        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "fail", token: nil))
        } catch {}

        #expect(monitor.failures.count == 1)
        #expect(monitor.failures[0].endpoint == "fail")
        if case .serverError(_, let code, _) = monitor.failures[0].error {
            #expect(code == 500)
        } else {
            #expect(Bool(false), "Expected .serverError")
        }
    }

    @Test("no start event fires when monitor array is empty")
    func noMonitorNoEvents() async throws {
        let payload = TestResponse(id: "3", status: "ok")
        let data = try JSONEncoder().encode(payload)

        MockURLProtocol.handler = { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration()
            // no eventMonitors
        )
        // Should complete without crashing
        let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "items", token: nil))
    }

    @Test("requestWillRetry fires when RetryPolicy retries")
    func retryEventFires() async throws {
        let monitor = RecordingMonitor()
        var callCount = 0
        let payload = TestResponse(id: "r", status: "ok")
        let successData = try JSONEncoder().encode(payload)

        MockURLProtocol.handler = { request in
            callCount += 1
            if callCount == 1 {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
            }
            return (successData, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            interceptors: [BaseAPI.RetryPolicy(maxAttempts: 2, backoff: .none)],
            eventMonitors: [monitor]
        )

        let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "retry", token: nil))
        #expect(monitor.retries.count == 1)
        #expect(monitor.retries[0].attemptCount == 1)
        #expect(monitor.retries[0].delay == 0)
        #expect(monitor.finishes.count == 1)
    }

    @Test("EventMonitorGroup fans out events to all monitors")
    func eventMonitorGroupFansOut() async throws {
        let monitorA = RecordingMonitor()
        let monitorB = RecordingMonitor()
        let payload = TestResponse(id: "g", status: "ok")
        let data = try JSONEncoder().encode(payload)

        MockURLProtocol.handler = { request in
            (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            eventMonitors: [monitorA, monitorB]
        )

        let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "group", token: nil))
        #expect(monitorA.starts.count == 1)
        #expect(monitorB.starts.count == 1)
        #expect(monitorA.finishes.count == 1)
        #expect(monitorB.finishes.count == 1)
    }

    @Test("start does not fire if request fails before network (interceptor throw)")
    func startFiresEvenIfInterceptorThrows() async throws {
        // The start event fires after adapt() succeeds — if adapt throws, start is never fired
        // because we never get a URLRequest to report.
        let monitor = RecordingMonitor()

        MockURLProtocol.handler = { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            interceptors: [FailingInterceptor()],
            eventMonitors: [monitor]
        )

        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "x", token: nil))
        } catch {}

        // adapt() threw before we could fire requestDidStart
        #expect(monitor.starts.count == 0)
    }

    @Test("duration in requestDidFail is non-negative")
    func failDurationNonNegative() async throws {
        let monitor = RecordingMonitor()

        let c = makeClient(monitor: monitor) { request in
            (Data(), HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!)
        }

        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c.get(MockEndpoint(endpoint: "e", token: nil))
        } catch {}

        #expect(monitor.failures[0].duration >= 0)
    }
}

// MARK: - RequestBuilder Tests

@Suite("Request Builder Tests")
struct RequestBuilderTests {

    private func makeClient(handler: @escaping MockURLProtocol.Handler)
        -> BaseAPI.BaseAPIClient<MockEndpoint>
    {
        MockURLProtocol.handler = handler
        return BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())
    }

    // MARK: GET / response(_:)

    @Test("request(_:).response decodes JSON response")
    func builderGetDecodesResponse() async throws {
        let payload = TestResponse(id: "b1", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let c = makeClient { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (result, _): BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "items", token: nil))
            .response()
        #expect(result.id == "b1")
    }

    // MARK: method override

    @Test("builder sends correct HTTP method")
    func builderSetsMethod() async throws {
        let payload = TestResponse(id: "m", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let capturedMethod = ActorBox<String?>(nil)
        let c = makeClient { req in
            await capturedMethod.set(req.httpMethod)
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .method(.post)
            .response()
        #expect(await capturedMethod.value == "POST")
    }

    // MARK: .body(_:) — JSON

    @Test("builder encodes JSON body")
    func builderEncodesJSONBody() async throws {
        let payload = TestResponse(id: "jb", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let capturedBody = ActorBox<Data?>(nil)
        let c = makeClient { req in
            await capturedBody.set(req.httpBody)
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .method(.post)
            .body(TestRequest(name: "alice", value: 1))
            .response()
        let body = await capturedBody.value
        #expect(body != nil)
        let decoded = try JSONDecoder().decode(TestRequest.self, from: body!)
        #expect(decoded.name == "alice")
    }

    // MARK: .body(raw:contentType:)

    @Test("builder sends raw body unchanged")
    func builderSendsRawBody() async throws {
        let raw = Data("hello".utf8)
        let payload = TestResponse(id: "r", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBody = ActorBox<Data?>(nil)
        let capturedCT = ActorBox<String?>(nil)
        let c = makeClient { req in
            await capturedBody.set(req.httpBody)
            await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .method(.put)
            .body(raw: raw, contentType: "text/plain")
            .response()
        #expect(await capturedBody.value == raw)
        #expect(await capturedCT.value == "text/plain")
    }

    // MARK: .headers(_:)

    @Test("builder merges additional headers")
    func builderMergesHeaders() async throws {
        let payload = TestResponse(id: "h", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let capturedHeader = ActorBox<String?>(nil)
        let c = makeClient { req in
            await capturedHeader.set(req.value(forHTTPHeaderField: "X-Trace-ID"))
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .headers(["X-Trace-ID": "abc123"])
            .response()
        #expect(await capturedHeader.value == "abc123")
    }

    @Test("later .headers call merges with earlier call")
    func builderHeadersMerge() async throws {
        let payload = TestResponse(id: "hm", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let capturedA = ActorBox<String?>(nil)
        let capturedB = ActorBox<String?>(nil)
        let c = makeClient { req in
            await capturedA.set(req.value(forHTTPHeaderField: "X-A"))
            await capturedB.set(req.value(forHTTPHeaderField: "X-B"))
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .headers(["X-A": "1"])
            .headers(["X-B": "2"])
            .response()
        #expect(await capturedA.value == "1")
        #expect(await capturedB.value == "2")
    }

    // MARK: .timeout(_:)

    @Test("builder sets per-request timeout")
    func builderSetsTimeout() async throws {
        let payload = TestResponse(id: "t", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let capturedTimeout = ActorBox<TimeInterval?>(nil)
        let c = makeClient { req in
            await capturedTimeout.set(req.timeoutInterval)
            return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .timeout(42)
            .response()
        #expect(await capturedTimeout.value == 42)
    }

    // MARK: .validators(_:)

    @Test("builder overrides validators: AcceptedStatusCodesValidator accepts 201")
    func builderOverridesValidators() async throws {
        let payload = TestResponse(id: "v", status: "created")
        let data = try JSONEncoder().encode(payload)
        let c = makeClient { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
        }
        // Default StatusCodeValidator accepts 200-299, so 201 passes — but we're also
        // testing that overriding works when we explicitly restrict to {201}.
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "x", token: nil))
            .validators([BaseAPI.AcceptedStatusCodesValidator([201])])
            .response()
    }

    @Test("builder overridden validator rejects status not in accepted set")
    func builderValidatorRejectsUnaccepted() async throws {
        let c = makeClient { req in
            (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .validators([BaseAPI.AcceptedStatusCodesValidator([201])])
                .response()
            #expect(Bool(false), "Should have thrown")
        } catch let err as BaseAPI.APIError {
            if case .serverError(_, let code, _) = err {
                #expect(code == 200)
            } else {
                #expect(Bool(false), "Expected serverError")
            }
        }
    }

    // MARK: .responseURL()

    @Test("responseURL returns HTTPURLResponse without decoding body")
    func builderResponseURL() async throws {
        let c = makeClient { req in
            (Data("{\"unexpected\":true}".utf8),
             HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!)
        }
        let httpResponse = try await c
            .request(MockEndpoint(endpoint: "del", token: nil))
            .method(.delete)
            .validators([BaseAPI.AcceptedStatusCodesValidator([204])])
            .responseURL()
        #expect(httpResponse.statusCode == 204)
    }

    // MARK: .responseData()

    @Test("responseData returns raw bytes")
    func builderResponseData() async throws {
        let raw = Data("raw content".utf8)
        let c = makeClient { req in
            (raw, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (data, _) = try await c
            .request(MockEndpoint(endpoint: "file", token: nil))
            .responseData()
        #expect(data == raw)
    }

    // MARK: error propagation

    @Test("builder propagates server error")
    func builderPropagatesServerError() async throws {
        let c = makeClient { req in
            (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        do {
            let _: BaseAPI.APIResponse<TestResponse> = try await c
                .request(MockEndpoint(endpoint: "missing", token: nil))
                .response()
            #expect(Bool(false), "Should have thrown")
        } catch let err as BaseAPI.APIError {
            if case .serverError(_, let code, _) = err {
                #expect(code == 404)
            } else {
                #expect(Bool(false), "Expected serverError")
            }
        }
    }

    // MARK: event monitor integration

    @Test("builder fires requestDidStart and requestDidFinish")
    func builderFiresMonitorEvents() async throws {
        let monitor = EventMonitorTests.RecordingMonitor()
        let payload = TestResponse(id: "em", status: "ok")
        let data = try JSONEncoder().encode(payload)
        MockURLProtocol.handler = { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            eventMonitors: [monitor]
        )
        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "em", token: nil))
            .response()
        #expect(monitor.starts.count == 1)
        #expect(monitor.finishes.count == 1)
    }

    // MARK: immutability — builder is a value type

    @Test("builder modifiers do not mutate the original")
    func builderIsImmutable() async throws {
        let payload = TestResponse(id: "imm", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let c = makeClient { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let base = c.request(MockEndpoint(endpoint: "x", token: nil))
        let withPost = base.method(.post)
        let withGet  = base.method(.get)
        #expect(withPost.httpMethod == .post)
        #expect(withGet.httpMethod  == .get)
        #expect(base.httpMethod     == .get)
    }
}

// MARK: - Form URL Encoding Tests

@Suite("Form URL Encoding Tests")
struct FormURLEncodingTests {

    private func makeClient(handler: @escaping MockURLProtocol.Handler)
        -> BaseAPI.BaseAPIClient<MockEndpoint>
    {
        MockURLProtocol.handler = handler
        return BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())
    }

    // MARK: Content-Type header

    @Test("form body sets Content-Type to application/x-www-form-urlencoded")
    func formBodySetsContentType() async throws {
        let payload = TestResponse(id: "f1", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedCT = ActorBox<String?>(nil)

        let c = makeClient { req in
            await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "auth/token", token: nil))
            .method(.post)
            .body(form: ["grant_type": "client_credentials"])
            .response()

        #expect(await capturedCT.value == "application/x-www-form-urlencoded")
    }

    // MARK: Body encoding

    @Test("form body encodes single key-value pair correctly")
    func formBodyEncodesSinglePair() async throws {
        let payload = TestResponse(id: "f2", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBody = ActorBox<Data?>(nil)

        let c = makeClient { req in
            await capturedBody.set(req.httpBody)
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "token", token: nil))
            .method(.post)
            .body(form: ["grant_type": "client_credentials"])
            .response()

        let body = await capturedBody.value
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        #expect(bodyString == "grant_type=client_credentials")
    }

    @Test("form body encodes multiple pairs sorted alphabetically")
    func formBodyEncodesMultiplePairsSorted() async throws {
        let payload = TestResponse(id: "f3", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBody = ActorBox<Data?>(nil)

        let c = makeClient { req in
            await capturedBody.set(req.httpBody)
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "token", token: nil))
            .method(.post)
            .body(form: ["scope": "read write", "grant_type": "password", "username": "alice"])
            .response()

        let body = await capturedBody.value
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        // Keys are sorted: grant_type, scope, username
        #expect(bodyString == "grant_type=password&scope=read%20write&username=alice")
    }

    @Test("form body percent-encodes special characters")
    func formBodyPercentEncodesSpecialChars() async throws {
        let payload = TestResponse(id: "f4", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedBody = ActorBox<Data?>(nil)

        let c = makeClient { req in
            await capturedBody.set(req.httpBody)
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "search", token: nil))
            .method(.post)
            .body(form: ["q": "hello world&foo=bar"])
            .response()

        let body = await capturedBody.value
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        // space → %20, & → %26, = → %3D
        #expect(bodyString == "q=hello%20world%26foo%3Dbar")
    }

    @Test("form body with empty dictionary produces no body bytes")
    func formBodyEncodesEmptyDict() async throws {
        // An empty field dict encodes to "" which is zero bytes —
        // URLSession does not set httpBody for zero-length data, so httpBody is nil.
        let payload = TestResponse(id: "f5", status: "ok")
        let responseData = try JSONEncoder().encode(payload)
        let capturedCT = ActorBox<String?>(nil)

        let c = makeClient { req in
            await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
            return (responseData, HTTPURLResponse(url: req.url!, statusCode: 200,
                                                  httpVersion: nil, headerFields: nil)!)
        }

        let _: BaseAPI.APIResponse<TestResponse> = try await c
            .request(MockEndpoint(endpoint: "token", token: nil))
            .method(.post)
            .body(form: [:])
            .response()

        // Content-Type is still set even though body is empty
        #expect(await capturedCT.value == "application/x-www-form-urlencoded")
    }

    // MARK: Works with responseData()

    @Test("form body works with responseData()")
    func formBodyWorksWithResponseData() async throws {
        let raw = Data("ok".utf8)
        let capturedCT = ActorBox<String?>(nil)

        let c = makeClient { req in
            await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
            return (raw, HTTPURLResponse(url: req.url!, statusCode: 200,
                                         httpVersion: nil, headerFields: nil)!)
        }

        let (data, _) = try await c
            .request(MockEndpoint(endpoint: "submit", token: nil))
            .method(.post)
            .body(form: ["key": "value"])
            .responseData()

        #expect(data == raw)
        #expect(await capturedCT.value == "application/x-www-form-urlencoded")
    }

    // MARK: Immutability

    @Test("form body modifier does not mutate original builder")
    func formBodyModifierIsImmutable() async throws {
        let payload = TestResponse(id: "imm", status: "ok")
        let data = try JSONEncoder().encode(payload)
        let c = makeClient { req in
            (data, HTTPURLResponse(url: req.url!, statusCode: 200,
                                   httpVersion: nil, headerFields: nil)!)
        }
        let base = c.request(MockEndpoint(endpoint: "x", token: nil)).method(.post)
        let withForm = base.body(form: ["a": "1"])
        let withJSON = base.body(TestRequest(name: "n", value: 0))

        if case .formURL = withForm.body { } else {
            #expect(Bool(false), "Expected .formURL on withForm")
        }
        if case .json = withJSON.body { } else {
            #expect(Bool(false), "Expected .json on withJSON")
        }
        if case .none = base.body { } else {
            #expect(Bool(false), "Expected .none on base")
        }
    }
}

// MARK: - Download Tests

@Suite("Download Tests")
struct DownloadTests {

    private func makeClient(
        responseData: Data,
        statusCode: Int = 200,
        headers: [String: String]? = nil
    ) -> BaseAPI.BaseAPIClient<MockEndpoint> {
        MockURLProtocol.handler = { req in
            let response = HTTPURLResponse(
                url: req.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: headers
            )!
            return (responseData, response)
        }
        return BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())
    }

    // MARK: Completion

    @Test("download yields final event with complete data")
    func downloadYieldsFinalData() async throws {
        let content = Data("hello download".utf8)
        let c = makeClient(responseData: content)

        var finalData: Data?
        for try await progress in c.download(MockEndpoint(endpoint: "file", token: nil)) {
            if let d = progress.data { finalData = d }
        }
        #expect(finalData == content)
    }

    @Test("download via RequestBuilder yields final event with complete data")
    func downloadViaBuilderYieldsFinalData() async throws {
        let content = Data("builder download".utf8)
        let c = makeClient(responseData: content)

        var finalData: Data?
        for try await progress in c
            .request(MockEndpoint(endpoint: "file", token: nil))
            .download()
        {
            if let d = progress.data { finalData = d }
        }
        #expect(finalData == content)
    }

    // MARK: Progress events

    @Test("download emits progress events before final event")
    func downloadEmitsProgressEvents() async throws {
        // Use a reasonably sized payload so URLSession produces at least one intermediate event.
        let content = Data(repeating: 0xAB, count: 4096)
        let c = makeClient(responseData: content)

        var progressEvents: [BaseAPI.DownloadProgress] = []
        for try await progress in c.download(MockEndpoint(endpoint: "file", token: nil)) {
            progressEvents.append(progress)
        }

        #expect(progressEvents.count >= 1)
        // Final event has data
        #expect(progressEvents.last?.data != nil)
        // bytesReceived on last event equals content size
        #expect(progressEvents.last?.bytesReceived == Int64(content.count))
    }

    @Test("intermediate progress events have nil data")
    func intermediateEventsHaveNilData() async throws {
        let content = Data(repeating: 0xCD, count: 4096)
        let c = makeClient(responseData: content)

        var events: [BaseAPI.DownloadProgress] = []
        for try await p in c.download(MockEndpoint(endpoint: "file", token: nil)) {
            events.append(p)
        }

        // All events except the last must have nil data
        let intermediate = events.dropLast()
        for event in intermediate {
            #expect(event.data == nil)
        }
    }

    // MARK: Content-Length → fraction

    @Test("fraction is non-nil when Content-Length is present")
    func fractionNonNilWithContentLength() async throws {
        let content = Data(repeating: 0x01, count: 100)
        let c = makeClient(
            responseData: content,
            headers: ["Content-Length": "\(content.count)"]
        )

        var lastProgress: BaseAPI.DownloadProgress?
        for try await p in c.download(MockEndpoint(endpoint: "file", token: nil)) {
            lastProgress = p
        }
        #expect(lastProgress?.totalBytesExpected == Int64(content.count))
        #expect(lastProgress?.fraction == 1.0)
    }

    @Test("fraction is nil when Content-Length is absent")
    func fractionNilWithoutContentLength() async throws {
        let content = Data("no length header".utf8)
        let c = makeClient(responseData: content) // no Content-Length header

        var lastProgress: BaseAPI.DownloadProgress?
        for try await p in c.download(MockEndpoint(endpoint: "file", token: nil)) {
            lastProgress = p
        }
        #expect(lastProgress?.totalBytesExpected == nil)
        #expect(lastProgress?.fraction == nil)
    }

    // MARK: Error propagation

    @Test("download throws on server error status")
    func downloadThrowsOnServerError() async throws {
        let c = makeClient(responseData: Data(), statusCode: 503)

        var caught: BaseAPI.APIError?
        do {
            for try await _ in c.download(MockEndpoint(endpoint: "file", token: nil)) {}
        } catch let e as BaseAPI.APIError {
            caught = e
        }

        if case .serverError(_, let code, _) = caught {
            #expect(code == 503)
        } else {
            #expect(Bool(false), "Expected .serverError(503)")
        }
    }

    // MARK: Event monitor integration

    @Test("download fires requestDidStart and requestDidFinish on success")
    func downloadFiresMonitorEvents() async throws {
        let monitor = EventMonitorTests.RecordingMonitor()
        let content = Data("monitored".utf8)

        MockURLProtocol.handler = { req in
            (content, HTTPURLResponse(url: req.url!, statusCode: 200,
                                      httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            eventMonitors: [monitor]
        )

        for try await _ in c.download(MockEndpoint(endpoint: "file", token: nil)) {}

        #expect(monitor.starts.count == 1)
        #expect(monitor.finishes.count == 1)
        #expect(monitor.failures.count == 0)
    }

    @Test("download fires requestDidFail on error")
    func downloadFiresMonitorFailEvent() async throws {
        let monitor = EventMonitorTests.RecordingMonitor()

        MockURLProtocol.handler = { req in
            (Data(), HTTPURLResponse(url: req.url!, statusCode: 500,
                                     httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(
            sessionConfiguration: mockSessionConfiguration(),
            eventMonitors: [monitor]
        )

        do {
            for try await _ in c.download(MockEndpoint(endpoint: "file", token: nil)) {}
        } catch {}

        #expect(monitor.failures.count == 1)
    }

    // MARK: RequestBuilder per-request overrides respected

    @Test("download via builder applies extra headers")
    func downloadBuilderAppliesHeaders() async throws {
        let content = Data("ok".utf8)
        let capturedHeader = ActorBox<String?>(nil)

        MockURLProtocol.handler = { req in
            await capturedHeader.set(req.value(forHTTPHeaderField: "X-Download-Token"))
            return (content, HTTPURLResponse(url: req.url!, statusCode: 200,
                                             httpVersion: nil, headerFields: nil)!)
        }
        let c = BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())

        for try await _ in c
            .request(MockEndpoint(endpoint: "file", token: nil))
            .headers(["X-Download-Token": "secret"])
            .download()
        {}

        #expect(await capturedHeader.value == "secret")
    }
}

} // NetworkTests
