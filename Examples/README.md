# APIClient Examples

This directory contains comprehensive examples demonstrating the capabilities of the APIClient package. Each example can be run independently and provides detailed explanations and best practices.

## 📁 Example Files

### 1. **BasicUsage.swift**
**Getting started with APIClient fundamentals**
- Defining API endpoints with protocols
- Creating data models with Codable
- Making GET, POST, PUT requests
- Basic error handling patterns
- Configuration options

**Run with:**
```bash
swift BasicUsage.swift
```

### 2. **AdvancedFeatures.swift**
**Production-ready features and patterns**
- Authentication and token management
- Analytics integration
- Retry logic with exponential backoff
- File upload with multipart data
- Request/response interception
- Environment-based configuration
- Testing utilities and mocking

**Run with:**
```bash
swift AdvancedFeatures.swift
```

## 🚀 Running Examples

### Prerequisites
- Swift 5.5+
- macOS 10.15+ / iOS 12+
- Foundation framework
- APIClient package

### Quick Start
1. Navigate to the Examples directory
2. Run any example directly with Swift:
   ```bash
   cd Examples
   swift BasicUsage.swift
   ```

### Integration with Xcode
1. Open the APIClient package in Xcode
2. Add the example files to your target
3. Uncomment the code sections in each example
4. Import the APIClient package at the top

## 📚 Learning Path

### For Beginners
1. Start with **BasicUsage.swift** to understand core concepts
2. Learn about endpoint definitions and data models
3. Practice with basic GET and POST requests
4. Understand error handling patterns

### For Production Applications
1. Study **AdvancedFeatures.swift** thoroughly
2. Implement authentication and token management
3. Add analytics and monitoring
4. Set up proper error handling and retry logic
5. Create testing utilities for your API layer

## 🔧 Customizing Examples

### Enabling Code Execution
The example files contain commented code blocks. To run them:

1. Uncomment the import statements:
   ```swift
   import APIClient
   ```

2. Uncomment the relevant code blocks

3. Replace example URLs with your actual API endpoints

4. Add your authentication tokens and API keys

### Modifying for Your API
- Change endpoint URLs to match your API
- Update data models to match your API responses
- Modify authentication headers as needed
- Adjust timeout and retry settings

## 🎯 Real-World Usage Patterns

### Basic API Integration
```swift
enum MyAPI: BaseAPI.APIEndpoint {
    case getData
    case postData
    
    var url: URL { /* your URLs */ }
    var stringValue: String { /* endpoint identifier */ }
    var authHeader: [String: String]? { /* your auth */ }
}

let client = BaseAPI.BaseAPIClient<MyAPI>()
let response: BaseAPI.APIResponse<MyData> = try await client.get(.getData)
```

### Authentication Flow
```swift
class AuthManager {
    static func authenticate() async throws -> String {
        // Your authentication logic
    }
    
    static func refreshToken() async throws -> String {
        // Your token refresh logic
    }
}

let client = BaseAPI.BaseAPIClient<MyAPI>(
    unauthorizedHandler: { endpoint in
        Task { try await AuthManager.refreshToken() }
    }
)
```

### Analytics Integration
```swift
class MyAnalytics: BaseAPI.APIAnalytics {
    func addAnalytics(endpoint: String, method: String, startTime: Date, 
                     endTime: Date, success: Bool, statusCode: Int?, error: String?) {
        // Send to your analytics service
        AnalyticsService.track("api_call", properties: [
            "endpoint": endpoint,
            "method": method,
            "success": success,
            "duration": endTime.timeIntervalSince(startTime)
        ])
    }
}
```

## 🔍 Common Integration Patterns

### SwiftUI Integration
```swift
@MainActor
class APIViewModel: ObservableObject {
    @Published var data: [MyData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiClient = BaseAPI.BaseAPIClient<MyAPI>()
    
    func loadData() async {
        isLoading = true
        do {
            let response: BaseAPI.APIResponse<[MyData]> = try await apiClient.get(.getData)
            data = response.data
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
```

### Combine Integration
```swift
import Combine

extension BaseAPI.BaseAPIClient {
    func getPublisher<T: Codable>(_ endpoint: Endpoint) -> AnyPublisher<T, BaseAPI.APIError> {
        Future { promise in
            Task {
                do {
                    let response: BaseAPI.APIResponse<T> = try await self.get(endpoint)
                    promise(.success(response.data))
                } catch let error as BaseAPI.APIError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.unknown))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}
```

## 🧪 Testing Examples

### Unit Testing
```swift
func testAPICall() async throws {
    let mockClient = MockAPIClient<MyAPI>()
    let expectedData = MyData(id: 1, name: "Test")
    mockClient.setMockResponse(expectedData, for: .getData)
    
    let response: BaseAPI.APIResponse<MyData> = try await mockClient.get(.getData)
    XCTAssertEqual(response.data.id, 1)
}
```

### Integration Testing
```swift
func testRealAPICall() async throws {
    let client = BaseAPI.BaseAPIClient<MyAPI>()
    
    do {
        let response: BaseAPI.APIResponse<[MyData]> = try await client.get(.getData)
        XCTAssertFalse(response.data.isEmpty)
    } catch {
        XCTFail("API call failed: \(error)")
    }
}
```

## 📊 Performance Considerations

### Optimization Tips
- **Reuse client instances** - Create once, use throughout app lifecycle
- **Configure timeouts** appropriately for your network conditions
- **Use connection pooling** through URLSession configuration
- **Implement caching** for frequently accessed data
- **Monitor analytics** to identify slow endpoints

### Memory Management
- APIClient instances are lightweight
- URLSession handles connection pooling automatically
- JSON encoding/decoding is handled efficiently
- Analytics data should be sent asynchronously

## 🔐 Security Best Practices

### Token Management
```swift
// Store tokens securely
KeychainManager.store(token, for: "api_token")

// Retrieve tokens safely
if let token = KeychainManager.retrieve("api_token") {
    // Use token in API calls
}
```

### Certificate Pinning
```swift
let sessionConfig = URLSessionConfiguration.default
// Configure certificate pinning if needed
let client = BaseAPI.BaseAPIClient<MyAPI>(sessionConfiguration: sessionConfig)
```

## 🚨 Error Handling Strategies

### User-Friendly Error Messages
```swift
extension BaseAPI.APIError {
    var userFriendlyMessage: String {
        switch self {
        case .networkError:
            return "Please check your internet connection"
        case .serverError(_, let code, _):
            return code >= 500 ? "Server is temporarily unavailable" : "Request failed"
        default:
            return "Something went wrong. Please try again"
        }
    }
}
```

### Retry Strategies
```swift
func performWithRetry<T: Codable>(
    endpoint: MyAPI,
    maxRetries: Int = 3
) async throws -> BaseAPI.APIResponse<T> {
    var lastError: Error?
    
    for attempt in 0...maxRetries {
        do {
            return try await client.get(endpoint)
        } catch {
            lastError = error
            if attempt < maxRetries {
                await Task.sleep(UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
            }
        }
    }
    
    throw lastError!
}
```

## 📖 Additional Resources

- [Main README](../README.md) - Package overview and installation
- [API Documentation](../Sources/) - Source code and implementation details
- [Swift Documentation](https://docs.swift.org/swift-book/) - Swift language guide
- [URLSession Guide](https://developer.apple.com/documentation/foundation/urlsession) - Foundation networking

## 🤝 Contributing Examples

To contribute new examples:
1. Follow the existing example structure
2. Include comprehensive comments
3. Provide real-world use cases
4. Add error handling examples
5. Update this README with your example
6. Test thoroughly before submitting

---

**Build robust APIs with confidence!** 🚀

