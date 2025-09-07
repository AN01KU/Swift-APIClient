# APIClient Package

A modern, type-safe HTTP API client built with Swift's async/await, providing a robust foundation for network communication in Swift applications.

## Features

- 🚀 **Modern Swift**: Built with async/await and modern Swift patterns
- 🔒 **Type Safety**: Strongly typed endpoints and responses using protocols
- 📊 **Analytics Support**: Built-in analytics tracking for API calls
- 🔄 **Automatic Retries**: Configurable retry mechanisms for failed requests
- 📁 **Multipart Upload**: Support for file uploads with form data
- ⚡ **Flexible Configuration**: Customizable session configuration and JSON coders
- 🎯 **Error Handling**: Comprehensive error types with detailed information
- 🧪 **Testable**: Designed for easy mocking and unit testing

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(path: "path/to/APIClient")
]
```

Or add it directly in Xcode:
1. File → Add Package Dependencies
2. Enter the package URL
3. Select the version/branch
4. Add to your target

## Quick Start

### 1. Define Your API Endpoints

```swift
import APIClient

enum MyAPIEndpoint: BaseAPI.APIEndpoint {
    case users
    case user(id: String)
    case createUser
    case updateUser(id: String)
    
    var url: URL {
        let baseURL = "https://api.example.com"
        switch self {
        case .users:
            return URL(string: "\(baseURL)/users")!
        case .user(let id):
            return URL(string: "\(baseURL)/users/\(id)")!
        case .createUser:
            return URL(string: "\(baseURL)/users")!
        case .updateUser(let id):
            return URL(string: "\(baseURL)/users/\(id)")!
        }
    }
    
    var stringValue: String {
        return url.absoluteString
    }
    
    var authHeader: [String: String]? {
        return ["Authorization": "Bearer \(getToken())"]
    }
}
```

### 2. Define Your Data Models

```swift
struct User: Codable {
    let id: String
    let name: String
    let email: String
}

struct CreateUserRequest: Codable {
    let name: String
    let email: String
}

struct UpdateUserRequest: Codable {
    let name: String?
    let email: String?
}
```

### 3. Create and Use the API Client

```swift
// Initialize the client
let apiClient = BaseAPI.BaseAPIClient<MyAPIEndpoint>()

// GET request
do {
    let response: BaseAPI.APIResponse<[User]> = try await apiClient.get(.users)
    let users = response.data
    print("Fetched \(users.count) users")
} catch {
    print("Error fetching users: \(error)")
}

// POST request
do {
    let newUser = CreateUserRequest(name: "John Doe", email: "john@example.com")
    let response: BaseAPI.APIResponse<User> = try await apiClient.post(.createUser, body: newUser)
    print("Created user: \(response.data)")
} catch {
    print("Error creating user: \(error)")
}
```

## Advanced Usage

### Custom Configuration

```swift
// Custom session configuration
let sessionConfig = URLSessionConfiguration.default
sessionConfig.timeoutIntervalForRequest = 30
sessionConfig.timeoutIntervalForResource = 60

// Custom JSON coders
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601

// Initialize with custom configuration
let apiClient = BaseAPI.BaseAPIClient<MyAPIEndpoint>(
    sessionConfiguration: sessionConfig,
    encoder: encoder,
    decoder: decoder
)
```

### Analytics Integration

```swift
class MyAnalytics: BaseAPI.APIAnalytics {
    func addAnalytics(endpoint: String, method: String, startTime: Date, 
                     endTime: Date, success: Bool, statusCode: Int?, error: String?) {
        let duration = endTime.timeIntervalSince(startTime)
        print("API Call: \(method) \(endpoint) - \(duration)ms - Success: \(success)")
        
        // Send to your analytics service
        // AnalyticsService.track(event: "api_call", properties: [...])
    }
}

let analytics = MyAnalytics()
let apiClient = BaseAPI.BaseAPIClient<MyAPIEndpoint>(analytics: analytics)
```

### Error Handling with Unauthorized Callback

```swift
let apiClient = BaseAPI.BaseAPIClient<MyAPIEndpoint>(
    unauthorizedHandler: { endpoint in
        print("Unauthorized access to \(endpoint.stringValue)")
        // Handle token refresh or redirect to login
        TokenManager.refreshToken()
    }
)
```

### Multipart File Upload

```swift
// Prepare file data
let fileURLs = [Bundle.main.url(forResource: "document", withExtension: "pdf")!]
let parameters = ["description": "Important document"] as [String: AnyObject]

let multipartData = BaseAPI.MultipartData(
    parameters: parameters,
    fileKeyName: "file",
    fileURLs: fileURLs
)

// Upload files
do {
    let response = try await apiClient.multipartUpload(.uploadDocument, method: .post, data: multipartData)
    print("Upload successful: \(response.statusCode)")
} catch {
    print("Upload failed: \(error)")
}
```

### Callback-Based API (Legacy Support)

```swift
// GET with callback
apiClient.get(.users) { (result: BaseAPI.APIResult<[User]>) in
    switch result {
    case .success(let response):
        print("Users: \(response.data)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}

// POST with callback
let newUser = CreateUserRequest(name: "Jane Doe", email: "jane@example.com")
apiClient.post(.createUser, body: newUser) { (result: BaseAPI.APIResult<User>) in
    switch result {
    case .success(let response):
        print("Created user: \(response.data)")
    case .failure(let error):
        print("Error: \(error.localizedDescription)")
    }
}
```

## Error Handling

The APIClient provides comprehensive error handling through the `APIError` enum:

```swift
do {
    let response = try await apiClient.get(.users)
    // Handle success
} catch let error as BaseAPI.APIError {
    switch error {
    case .missingAuthHeader:
        // Handle missing authentication
        print("Authentication required")
        
    case .networkError(let message):
        // Handle network issues
        print("Network error: \(message)")
        
    case .serverError(let response, let code, let requestID):
        // Handle server errors
        print("Server error \(code), Request ID: \(requestID)")
        
    case .decodingFailed(let response, let message):
        // Handle JSON decoding errors
        print("Failed to decode response: \(message)")
        
    case .encodingFailed:
        // Handle request encoding errors
        print("Failed to encode request")
        
    case .invalidResponse:
        // Handle invalid responses
        print("Invalid response received")
        
    case .unknown:
        // Handle unknown errors
        print("Unknown error occurred")
    }
}
```

## API Reference

### Core Types

- **`BaseAPI.BaseAPIClient<Endpoint>`**: Main API client class
- **`BaseAPI.APIEndpoint`**: Protocol for defining API endpoints
- **`BaseAPI.APIError`**: Comprehensive error enum
- **`BaseAPI.APIResponse<T>`**: Response wrapper with data and HTTP response
- **`BaseAPI.MultipartData`**: Container for multipart upload data
- **`BaseAPI.APIAnalytics`**: Protocol for analytics integration

### HTTP Methods

- **GET**: `get(_:)` - Retrieve data
- **POST**: `post(_:body:)` - Create or send data  
- **PUT**: `put(_:body:)` - Update data
- **DELETE**: Available through custom implementation
- **Multipart Upload**: `multipartUpload(_:method:data:)` - File uploads

### Configuration Options

- **Session Configuration**: Custom `URLSessionConfiguration`
- **JSON Encoding/Decoding**: Custom `JSONEncoder` and `JSONDecoder`
- **Analytics**: Custom analytics tracking
- **Unauthorized Handler**: Handle 401 responses automatically
- **Retry Logic**: Built into the session configuration

## Testing

The package includes comprehensive tests covering:

- ✅ API client initialization and configuration
- ✅ Error handling and classification
- ✅ Data structures and models
- ✅ Extension functions and utilities
- ✅ Mock implementations for testing

Run tests with:
```bash
swift test
```

### Testing Your API Client

```swift
// Mock endpoint for testing
struct MockEndpoint: BaseAPI.APIEndpoint {
    let endpoint: String
    let token: String?
    
    var url: URL { URL(string: "https://api.test.com/\(endpoint)")! }
    var stringValue: String { endpoint }
    var authHeader: [String: String]? { 
        guard let token = token else { return [:] }
        return ["Authorization": "Bearer \(token)"] 
    }
}

// Test with mock
let client = BaseAPI.BaseAPIClient<MockEndpoint>()
let endpoint = MockEndpoint(endpoint: "test", token: "mock-token")
// Perform tests...
```

## Best Practices

### 1. **Endpoint Organization**
- Group related endpoints in enums
- Use associated values for dynamic parameters
- Keep endpoint logic simple and focused

### 2. **Error Handling**
- Always handle specific error cases
- Provide meaningful error messages to users
- Log errors for debugging and monitoring

### 3. **Configuration**
- Use environment-specific configurations
- Keep sensitive data (tokens, keys) secure
- Configure appropriate timeouts for your use case

### 4. **Performance**
- Reuse API client instances
- Configure session for connection pooling
- Use appropriate JSON coding strategies

### 5. **Testing**
- Mock network calls in unit tests
- Test error scenarios thoroughly
- Use dependency injection for testability

## Requirements

- Swift 5.5+
- macOS 10.15+ / iOS 12+
- Foundation framework

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This package is available under the MIT license. See the LICENSE file for more info.

---

**Built for modern Swift development** 🚀

