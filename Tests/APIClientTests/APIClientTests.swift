import Foundation
import Testing

@testable import APIClient

// MARK: - Test Mock Endpoint
struct MockEndpoint: BaseAPI.APIEndpoint {
    let endpoint: String
    let token: String?

    var url: URL {
        return URL(string: "https://api.example.com/\(endpoint)")!
    }

    var stringValue: String {
        return endpoint
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

// MARK: - Test Logger
class TestLogger: BaseAPI.APIClientLoggingProtocol {
    var loggedMessages: [String] = []

    func info(_ value: String) {
        let message = "[TEST INFO] \(value)"
        print(message)
        loggedMessages.append(message)
    }

    func debug(_ value: String) {
        let message = "[TEST DEBUG] \(value)"
        print(message)
        loggedMessages.append(message)
    }

    func error(_ value: String) {
        let message = "[TEST ERROR] \(value)"
        print(message)
        loggedMessages.append(message)
    }

    func warn(_ value: String) {
        let message = "[TEST WARN] \(value)"
        print(message)
        loggedMessages.append(message)
    }

    func clearLogs() {
        loggedMessages.removeAll()
    }
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
    @Test("BaseAPI initialization")
    func baseAPIInitialization() throws {
        let baseAPI = BaseAPI()
        // BaseAPI initializes successfully
        #expect(type(of: baseAPI) == BaseAPI.self)
    }

    @Test("BaseAPIClient initialization")
    func baseAPIClientInitialization() throws {
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(logger: nil)
        // BaseAPIClient initializes successfully
        #expect(type(of: client) == BaseAPI.BaseAPIClient<MockEndpoint>.self)
    }

    @Test("BaseAPIClient initialization with logger")
    func baseAPIClientInitializationWithLogger() throws {
        let logger = TestLogger()
        let analytics = MockAnalytics()
        let client = BaseAPI.BaseAPIClient<MockEndpoint>(
            analytics: analytics,
            logger: logger
        )
        // BaseAPIClient initializes successfully with logger
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

    // MARK: - Logger Tests
    @Test("TestLogger functionality")
    func testLoggerFunctionality() throws {
        let logger = TestLogger()

        logger.info("Test info message")
        logger.debug("Test debug message")
        logger.error("Test error message")
        logger.warn("Test warning message")

        #expect(logger.loggedMessages.count == 4)
        #expect(logger.loggedMessages[0].contains("[TEST INFO]"))
        #expect(logger.loggedMessages[1].contains("[TEST DEBUG]"))
        #expect(logger.loggedMessages[2].contains("[TEST ERROR]"))
        #expect(logger.loggedMessages[3].contains("[TEST WARN]"))

        logger.clearLogs()
        #expect(logger.loggedMessages.isEmpty)
    }

    @Test("API logging protocol conformance")
    func apiLoggingProtocolConformance() throws {
        let logger = TestLogger()
        let protocol_: BaseAPI.APIClientLoggingProtocol = logger

        // Should be able to call all methods through protocol
        protocol_.info("Protocol info test")
        protocol_.debug("Protocol debug test")
        protocol_.error("Protocol error test")
        protocol_.warn("Protocol warn test")

        #expect(logger.loggedMessages.count == 4)
    }
}
