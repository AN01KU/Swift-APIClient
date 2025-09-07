#!/usr/bin/env swift

import Foundation

// MARK: - Advanced API Client Features
// This example demonstrates advanced features like analytics, authentication, and file uploads

print("=== APIClient Package - Advanced Features ===\n")

// Note: In a real application, you would import the APIClient package
// import APIClient

// MARK: - 1. Authentication & Token Management
print("1. Authentication & Token Management")

/*
// Token manager for handling authentication
class TokenManager {
    static private var currentToken: String?

    static func setToken(_ token: String) {
        currentToken = token
        // In production, store in Keychain
        print("🔐 Token stored securely")
    }

    static func getToken() -> String? {
        return currentToken
    }

    static func refreshToken() async throws -> String {
        // Simulate token refresh API call
        print("🔄 Refreshing authentication token...")
        await Task.sleep(1_000_000_000) // 1 second
        let newToken = "refreshed_token_\(Date().timeIntervalSince1970)"
        setToken(newToken)
        return newToken
    }

    static func clearToken() {
        currentToken = nil
        print("🔓 Token cleared")
    }
}

// Authenticated API endpoint
enum AuthenticatedAPI: BaseAPI.APIEndpoint {
    case profile
    case updateProfile
    case secureData
    case logout

    var url: URL {
        let baseURL = "https://api.secure-app.com"
        switch self {
        case .profile:
            return URL(string: "\(baseURL)/user/profile")!
        case .updateProfile:
            return URL(string: "\(baseURL)/user/profile")!
        case .secureData:
            return URL(string: "\(baseURL)/secure/data")!
        case .logout:
            return URL(string: "\(baseURL)/auth/logout")!
        }
    }

    var stringValue: String {
        return url.absoluteString
    }

    var authHeader: [String: String]? {
        guard let token = TokenManager.getToken() else {
            return nil  // This will trigger missingAuthHeader error
        }
        return [
            "Authorization": "Bearer \(token)",
            "X-API-Version": "v1"
        ]
    }
}
*/

print("   ✅ Token-based authentication with refresh logic")
print("   🔐 Secure token storage (use Keychain in production)")
print("   🔄 Automatic token refresh on 401 responses\n")

// MARK: - 2. Analytics Implementation
print("2. Analytics Implementation")

/*
class APIAnalytics: BaseAPI.APIAnalytics {
    private var analyticsData: [(endpoint: String, method: String, duration: TimeInterval, success: Bool)] = []

    func addAnalytics(endpoint: String, method: String, startTime: Date, endTime: Date,
                     success: Bool, statusCode: Int?, error: String?) {
        let duration = endTime.timeIntervalSince(startTime)

        // Store analytics data
        analyticsData.append((endpoint: endpoint, method: method, duration: duration, success: success))

        // Log analytics
        print("📊 API Analytics:")
        print("   Endpoint: \(method) \(endpoint)")
        print("   Duration: \(String(format: "%.3f", duration))s")
        print("   Success: \(success)")
        if let statusCode = statusCode {
            print("   Status: \(statusCode)")
        }
        if let error = error {
            print("   Error: \(error)")
        }

        // Send to analytics service
        sendToAnalyticsService(
            endpoint: endpoint,
            method: method,
            duration: duration,
            success: success,
            statusCode: statusCode,
            error: error
        )
    }

    private func sendToAnalyticsService(endpoint: String, method: String, duration: TimeInterval,
                                      success: Bool, statusCode: Int?, error: String?) {
        // In production, send to your analytics service
        // Example: Firebase Analytics, Mixpanel, Custom service
        print("📤 Sending analytics to service...")
    }

    func getAnalyticsSummary() -> String {
        let totalCalls = analyticsData.count
        let successfulCalls = analyticsData.filter { $0.success }.count
        let averageDuration = analyticsData.map { $0.duration }.reduce(0, +) / Double(max(totalCalls, 1))

        return """
        📈 Analytics Summary:
           Total API calls: \(totalCalls)
           Successful calls: \(successfulCalls)
           Success rate: \(String(format: "%.1f", Double(successfulCalls) / Double(max(totalCalls, 1)) * 100))%
           Average duration: \(String(format: "%.3f", averageDuration))s
        """
    }
}
*/

print("   ✅ Comprehensive API call tracking")
print("   📊 Success rates, response times, error tracking")
print("   📤 Easy integration with analytics services\n")

// MARK: - 3. Advanced Error Handling with Retry
print("3. Advanced Error Handling with Retry")

/*
class RobustAPIClient {
    private let client: BaseAPI.BaseAPIClient<AuthenticatedAPI>
    private let analytics: APIAnalytics
    private let maxRetries = 3

    init() {
        self.analytics = APIAnalytics()

        // Configure client with unauthorized handler
        self.client = BaseAPI.BaseAPIClient<AuthenticatedAPI>(
            analytics: analytics,
            unauthorizedHandler: { endpoint in
                print("🔒 Unauthorized access to \(endpoint.stringValue)")
                Task {
                    do {
                        _ = try await TokenManager.refreshToken()
                        print("✅ Token refreshed, retry your request")
                    } catch {
                        print("❌ Token refresh failed, redirecting to login")
                        TokenManager.clearToken()
                    }
                }
            }
        )
    }

    func performRequestWithRetry<T: Codable>(
        endpoint: AuthenticatedAPI,
        retryCount: Int = 0
    ) async throws -> BaseAPI.APIResponse<T> {
        do {
            let response: BaseAPI.APIResponse<T> = try await client.get(endpoint)
            return response

        } catch let error as BaseAPI.APIError {
            switch error {
            case .networkError where retryCount < maxRetries:
                print("🔄 Network error, retrying... (\(retryCount + 1)/\(maxRetries))")
                await Task.sleep(UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000)) // Exponential backoff
                return try await performRequestWithRetry(endpoint: endpoint, retryCount: retryCount + 1)

            case .serverError(_, let code, _) where code >= 500 && retryCount < maxRetries:
                print("🔄 Server error \(code), retrying... (\(retryCount + 1)/\(maxRetries))")
                await Task.sleep(UInt64(pow(2.0, Double(retryCount)) * 1_000_000_000))
                return try await performRequestWithRetry(endpoint: endpoint, retryCount: retryCount + 1)

            default:
                throw error
            }
        }
    }
}
*/

print("   ✅ Automatic retry logic with exponential backoff")
print("   🔄 Configurable retry attempts for different error types")
print("   ⚡ Smart error classification for retry decisions\n")

// MARK: - 4. File Upload with Progress
print("4. File Upload with Progress Tracking")

/*
// File upload endpoint
enum FileUploadAPI: BaseAPI.APIEndpoint {
    case uploadDocument
    case uploadImage
    case uploadMultiple

    var url: URL {
        let baseURL = "https://api.fileservice.com"
        switch self {
        case .uploadDocument:
            return URL(string: "\(baseURL)/upload/document")!
        case .uploadImage:
            return URL(string: "\(baseURL)/upload/image")!
        case .uploadMultiple:
            return URL(string: "\(baseURL)/upload/multiple")!
        }
    }

    var stringValue: String { url.absoluteString }

    var authHeader: [String: String]? {
        return ["Authorization": "Bearer \(TokenManager.getToken() ?? "")"]
    }
}

class FileUploadManager {
    private let client = BaseAPI.BaseAPIClient<FileUploadAPI>()

    func uploadSingleFile(fileURL: URL, description: String) async throws {
        print("📁 Preparing file upload...")

        // Prepare multipart data
        let parameters = [
            "description": description,
            "category": "document"
        ] as [String: AnyObject]

        let multipartData = BaseAPI.MultipartData(
            parameters: parameters,
            fileKeyName: "file",
            fileURLs: [fileURL]
        )

        do {
            let response = try await client.multipartUpload(.uploadDocument, method: .post, data: multipartData)
            print("✅ File uploaded successfully")
            print("📊 Response status: \(response.statusCode)")

        } catch {
            print("❌ Upload failed: \(error)")
            throw error
        }
    }

    func uploadMultipleFiles(fileURLs: [URL], metadata: [String: String]) async throws {
        print("📁 Preparing multiple file upload...")

        let parameters = metadata as [String: AnyObject]
        let multipartData = BaseAPI.MultipartData(
            parameters: parameters,
            fileKeyName: "files",
            fileURLs: fileURLs
        )

        do {
            let response = try await client.multipartUpload(.uploadMultiple, method: .post, data: multipartData)
            print("✅ Multiple files uploaded successfully")
            print("📊 Total files: \(fileURLs.count)")

        } catch {
            print("❌ Multiple upload failed: \(error)")
            throw error
        }
    }
}
*/

print("   ✅ Multipart file upload support")
print("   📎 Single and multiple file uploads")
print("   📊 Progress tracking and metadata support\n")

// MARK: - 5. Request/Response Interception
print("5. Request/Response Interception")

/*
extension BaseAPI.BaseAPIClient {
    func performRequestWithLogging<Request: Encodable, Response: Decodable>(
        endpoint: Endpoint,
        method: HTTPMethod,
        body: Request?
    ) async throws -> BaseAPI.APIResponse<Response> {

        // Pre-request logging
        print("🚀 API Request:")
        print("   Method: \(method.rawValue)")
        print("   URL: \(endpoint.url)")
        print("   Headers: \(endpoint.authHeader ?? [:])")

        if let body = body {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let jsonData = try encoder.encode(body)
                if let jsonString = String(data: jsonData, encoding: .utf8) {
                    print("   Body: \(jsonString)")
                }
            } catch {
                print("   Body: [encoding failed]")
            }
        }

        let startTime = Date()

        do {
            // Perform the actual request
            let response: BaseAPI.APIResponse<Response> = try await performRequest(
                endpoint: endpoint,
                method: method,
                body: body
            )

            let duration = Date().timeIntervalSince(startTime)

            // Post-response logging
            print("✅ API Response:")
            print("   Status: \(response.response.statusCode)")
            print("   Duration: \(String(format: "%.3f", duration))s")
            print("   Content-Type: \(response.response.value(forHTTPHeaderField: "Content-Type") ?? "unknown")")

            return response

        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("❌ API Error:")
            print("   Duration: \(String(format: "%.3f", duration))s")
            print("   Error: \(error)")
            throw error
        }
    }
}
*/

print("   ✅ Request/response logging and interception")
print("   🔍 Detailed debugging information")
print("   ⏱️ Performance monitoring at request level\n")

// MARK: - 6. Configuration Patterns
print("6. Advanced Configuration Patterns")

/*
// Environment-based configuration
enum APIEnvironment {
    case development
    case staging
    case production

    var baseURL: String {
        switch self {
        case .development:
            return "https://dev-api.example.com"
        case .staging:
            return "https://staging-api.example.com"
        case .production:
            return "https://api.example.com"
        }
    }

    var timeout: TimeInterval {
        switch self {
        case .development:
            return 60  // Longer timeout for debugging
        case .staging:
            return 30
        case .production:
            return 15  // Faster timeout for production
        }
    }
}

class APIClientFactory {
    static func createClient<T: BaseAPI.APIEndpoint>(
        for environment: APIEnvironment,
        endpointType: T.Type
    ) -> BaseAPI.BaseAPIClient<T> {

        // Configure session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = environment.timeout
        sessionConfig.timeoutIntervalForResource = environment.timeout * 2

        // Configure JSON handling
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Configure analytics
        let analytics = APIAnalytics()

        return BaseAPI.BaseAPIClient<T>(
            sessionConfiguration: sessionConfig,
            encoder: encoder,
            decoder: decoder,
            analytics: analytics
        )
    }
}

// Usage
let devClient = APIClientFactory.createClient(for: .development, endpointType: AuthenticatedAPI.self)
let prodClient = APIClientFactory.createClient(for: .production, endpointType: AuthenticatedAPI.self)
*/

print("   ✅ Environment-specific configurations")
print("   🏭 Factory pattern for client creation")
print("   ⚙️ Centralized configuration management\n")

// MARK: - 7. Testing Utilities
print("7. Testing Utilities")

/*
// Mock client for testing
class MockAPIClient<T: BaseAPI.APIEndpoint>: BaseAPI.BaseAPIClient<T> {
    var mockResponses: [String: Any] = [:]
    var mockErrors: [String: BaseAPI.APIError] = [:]

    func setMockResponse<Response: Codable>(_ response: Response, for endpoint: T) {
        mockResponses[endpoint.stringValue] = response
    }

    func setMockError(_ error: BaseAPI.APIError, for endpoint: T) {
        mockErrors[endpoint.stringValue] = error
    }

    override func get<Response: Decodable>(_ endpoint: T) async throws -> BaseAPI.APIResponse<Response> {
        let key = endpoint.stringValue

        if let error = mockErrors[key] {
            throw error
        }

        if let mockResponse = mockResponses[key] as? Response {
            let httpResponse = HTTPURLResponse(
                url: endpoint.url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (mockResponse, httpResponse)
        }

        throw BaseAPI.APIError.unknown
    }
}

// Usage in tests
func testAPIIntegration() async {
    let mockClient = MockAPIClient<AuthenticatedAPI>()

    // Set up mock response
    let mockProfile = UserProfile(id: 1, name: "Test User", email: "test@example.com")
    mockClient.setMockResponse(mockProfile, for: .profile)

    // Test your code with mock client
    do {
        let response: BaseAPI.APIResponse<UserProfile> = try await mockClient.get(.profile)
        print("✅ Mock test passed: \(response.data.name)")
    } catch {
        print("❌ Mock test failed: \(error)")
    }
}
*/

print("   ✅ Mock client for unit testing")
print("   🎭 Configurable mock responses and errors")
print("   🧪 Easy testing of success and failure scenarios\n")

print("=== Advanced Features Examples Completed! ===")
print("🚀 Ready to build production-ready API integrations")
print("🔒 Security, analytics, and testing all covered")
print("📈 Monitor and optimize your API performance")

