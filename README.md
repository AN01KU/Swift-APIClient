# APIClient

A modern, type-safe HTTP API client built with Swift's async/await, providing a robust foundation for network communication in Swift applications.

## Features

- Modern Swift with async/await and callback support
- Type-safe endpoints and responses using protocols
- Built-in analytics tracking for API calls
- Multipart upload support for file uploads
- Flexible configuration with custom session settings
- Comprehensive error handling with detailed information
- Designed for easy testing and mocking

## Installation

Add APIClient to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/APIClient.git", from: "1.0.0")
]
```

## Quick Start

### 1. Define Your API Endpoints

Create an enum conforming to `BaseAPI.APIEndpoint`:

```swift
enum MyAPI: BaseAPI.APIEndpoint {
    case users
    case user(id: String)

    var url: URL { /* return endpoint URL */ }
    var stringValue: String { /* return string representation */ }
    var authHeader: [String: String]? { /* return auth headers */ }
}
```

### 2. Create Data Models

Define Codable structs for your API responses:

```swift
struct User: Codable {
    let id: String
    let name: String
    let email: String
}
```

### 3. Use the API Client

```swift
let client = BaseAPI.BaseAPIClient<MyAPI>()

// Async/await
let response: BaseAPI.APIResponse<User> = try await client.get(.user(id: "123"))
let user = response.data

// Callback-based
client.get(.user(id: "123")) { (result: BaseAPI.APIResult<User>) in
    // Handle result
}
```

## Complete Example

For a comprehensive implementation example including:
- Complete API endpoint definitions
- Data model implementations
- Error handling strategies
- Analytics integration
- Multipart file uploads
- Advanced configuration

See: [Examples/ExampleUsage.swift](Examples/ExampleUsage.swift)

## Configuration

### BaseAPIClient Initialization

```swift
let client = BaseAPI.BaseAPIClient<YourEndpoint>(
    sessionConfiguration: URLSessionConfiguration.default,
    encoder: JSONEncoder(),
    decoder: JSONDecoder(),
    analytics: YourAnalytics(),
    logger: APIClientLogger(),
    unauthorizedHandler: { endpoint in
        // Handle 401 responses
    }
)
```

### Configuration Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `sessionConfiguration` | `URLSessionConfiguration` | Custom session settings |
| `encoder` | `JSONEncoder` | Custom JSON encoder |
| `decoder` | `JSONDecoder` | Custom JSON decoder |
| `analytics` | `APIAnalytics?` | Analytics tracking implementation |
| `logger` | `APIClientLoggingProtocol?` | Logging implementation |
| `unauthorizedHandler` | `((Endpoint) -> Void)?` | Handler for 401 responses |

## Protocols

### APIEndpoint Protocol

```swift
public protocol APIEndpoint: Equatable {
    var url: URL { get }
    var stringValue: String { get }
    var authHeader: [String: String]? { get }
}
```

### APIAnalytics Protocol

```swift
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
```

## Error Handling

The APIClient provides comprehensive error handling:

```swift
public enum APIError: Error {
    case missingAuthHeader
    case encodingFailed
    case networkError(String)
    case invalidResponse(response: URLResponse)
    case serverError(response: HTTPURLResponse, code: Int, requestID: String)
    case decodingFailed(response: HTTPURLResponse, error: String)
    case unknown
}
```

Each error provides detailed information and appropriate handling context.

## HTTP Methods

The APIClient supports all standard HTTP methods:

| Method | Signature | Description |
|--------|-----------|-------------|
| GET | `get<Response>(_:)` | Retrieve data from endpoint |
| POST | `post<Request, Response>(_:body:)` | Send data and receive response |
| PUT | `put<Request>(_:body:)` | Update entire resource |
| PATCH | `patch<Request>(_:body:)` | Partial resource update |
| DELETE | `delete(_:)` / `delete<Response>(_:)` | Delete resource, optionally with response |
| Multipart | `multipartUpload(_:method:data:)` | Upload files with form data |

All methods support both async/await and callback-based patterns.

### Examples

**GET with async/await:**
```swift
let response: BaseAPI.APIResponse<User> = try await client.get(.user(id: "123"))
```

**POST with async/await:**
```swift
let request = CreateUserRequest(name: "John", email: "john@example.com")
let response: BaseAPI.APIResponse<User> = try await client.post(.users, body: request)
```

**PATCH with async/await:**
```swift
let updates = UserUpdate(name: "Jane")
let response: HTTPURLResponse = try await client.patch(.user(id: "123"), body: updates)
```

**DELETE with async/await:**
```swift
let response: HTTPURLResponse = try await client.delete(.user(id: "123"))
```

**Callback-based (all methods support this):**
```swift
client.get(.user(id: "123")) { (result: BaseAPI.APIResult<User>) in
    switch result {
    case .success(let response):
        let user = response.data
    case .failure(let error):
        // Handle error
    }
}
```

## Testing

The package includes comprehensive tests covering all functionality:

```bash
swift test
```

Test coverage includes:
- All HTTP methods (GET, POST, PUT, PATCH, DELETE)
- Async/await and callback patterns
- Error handling and edge cases
- Analytics and logging integration
- Multipart upload functionality
- Authentication handling
- Data encoding/decoding

For testing your implementation, create mock endpoints and use dependency injection patterns supported by the client design:

```swift
struct MockEndpoint: BaseAPI.APIEndpoint {
    let endpoint: String
    let token: String?

    var url: URL { /* mock URL */ }
    var stringValue: String { endpoint }
    var authHeader: [String: String]? { /* mock auth */ }
}

let client = BaseAPI.BaseAPIClient<MockEndpoint>()
```

## Formatting

```
swift-format -i ./Sources ./Tests --recursive
```

## Requirements

- Swift 5.9+
- macOS 12+ / iOS 13+
- Foundation framework

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Follow Swift API Design Guidelines
6. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
