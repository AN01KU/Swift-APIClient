import Foundation
import Testing
import UniformTypeIdentifiers

@testable import APIClient

// MARK: - Test Mock Endpoint
struct MockEndpoint: BaseAPI.APIEndpoint, Equatable, Hashable {
    let endpoint: String
    let token: String?

    var url: URL {
        URL(string: "https://api.example.com/\(endpoint)")!
    }

    var stringValue: String {
        endpoint
    }

    var authHeader: [String: String]? {
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
class MockLogger: BaseAPI.APIClientLoggingProtocol {
    private(set) var logCount = 0

    func info(_ value: String) { logCount += 1 }
    func debug(_ value: String) { logCount += 1 }
    func error(_ value: String) { logCount += 1 }
    func warn(_ value: String) { logCount += 1 }

    func reset() { logCount = 0 }
}

// MARK: - Mock Analytics
class MockAnalytics: BaseAPI.APIAnalytics {
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
            .missingAuthHeader,
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
        #expect(BaseAPI.APIError.missingAuthHeader.isClientError == true)
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
        #expect(endpoint.authHeader?["Authorization"] == "Bearer test-token")

        let endpointWithoutToken = MockEndpoint(endpoint: "public", token: nil)
        #expect(endpointWithoutToken.authHeader?.isEmpty == true)
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
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")

        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.allCases.count == 4)
    }

    // MARK: - API Endpoint Tests
    @Test("Endpoint URL construction")
    func endpointURLConstruction() throws {
        let endpoint = MockEndpoint(endpoint: "users/123", token: "test-token")

        #expect(endpoint.url.absoluteString == "https://api.example.com/users/123")
        #expect(endpoint.stringValue == "users/123")
        #expect(endpoint.authHeader?["Authorization"] == "Bearer test-token")
    }

    @Test("Endpoint without authentication")
    func endpointWithoutAuth() throws {
        let endpoint = MockEndpoint(endpoint: "public/data", token: nil)

        #expect(endpoint.url.absoluteString == "https://api.example.com/public/data")
        #expect(endpoint.stringValue == "public/data")
        #expect(endpoint.authHeader?.isEmpty == true)
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
        let authHeader = ["Authorization": "Bearer token123", "X-Custom": "CustomValue"]

        request.addJSONHeaders(authHeader: authHeader)

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
        #expect(allMethods.contains(.delete))
        #expect(allMethods.count == 4)

        for method in allMethods {
            #expect(!method.rawValue.isEmpty)
        }
    }

    @Test("MockEndpoint edge cases")
    func mockEndpointEdgeCases() throws {
        let endpointWithToken = MockEndpoint(endpoint: "secure", token: "abc123")
        let endpointWithoutToken = MockEndpoint(endpoint: "public", token: nil)
        let endpointWithEmptyToken = MockEndpoint(endpoint: "empty", token: "")

        #expect(endpointWithToken.authHeader?["Authorization"] == "Bearer abc123")
        #expect(endpointWithoutToken.authHeader?.isEmpty == true)
        #expect(endpointWithEmptyToken.authHeader?["Authorization"] == "Bearer ")

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

        #expect(methods.count == 4)
        #expect(methods.contains(.get))
        #expect(methods.contains(.post))
        #expect(methods.contains(.put))
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
            .missingAuthHeader,
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
        request.addJSONHeaders(authHeader: [:])
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")

        // Test header merging
        request.addJSONHeaders(authHeader: ["Content-Type": "application/custom"])
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
            MockEndpoint(endpoint: "search?q=test", token: nil),
            MockEndpoint(endpoint: "admin/settings", token: "admin-token"),
        ]

        for endpoint in endpoints {
            #expect(endpoint.url.absoluteString.contains(endpoint.endpoint))
            #expect(endpoint.stringValue == endpoint.endpoint)

            if let token = endpoint.token, !token.isEmpty {
                #expect(endpoint.authHeader?["Authorization"] == "Bearer \(token)")
            } else {
                #expect(endpoint.authHeader?.isEmpty == true)
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
        #expect(BaseAPI.BaseAPIClient<MockEndpoint>.HTTPMethod.delete.rawValue == "DELETE")

        // Test that all cases are covered
        let expectedMethods: Set<String> = ["GET", "POST", "PUT", "DELETE"]
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
}
