import Foundation
import Testing
import UniformTypeIdentifiers

@testable import APIClient

// MARK: - Test Endpoint

struct MockEndpoint: BaseAPI.APIEndpoint, Equatable, Hashable {
    let endpoint: String
    let token: String?

    var baseURL: URL { URL(string: "https://api.example.com")! }
    var path: String { endpoint }

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

// MARK: - Mock Logger

final class MockLogger: BaseAPI.APIClientLoggingProtocol, @unchecked Sendable {
    private(set) var logCount = 0

    func info(_ value: String) { logCount += 1 }
    func debug(_ value: String) { logCount += 1 }
    func error(_ value: String) { logCount += 1 }
    func warn(_ value: String) { logCount += 1 }

    func reset() { logCount = 0 }
}

// MARK: - Mock Interceptors

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
            endpoint: String, method: String, startTime: Date, endTime: Date,
            success: Bool, statusCode: Int?, error: String?
        )] = []

    func addAnalytics(
        endpoint: String, method: String, startTime: Date, endTime: Date,
        success: Bool, statusCode: Int?, error: String?
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

// MARK: - Helpers

/// Thread-safe box for capturing values inside async closures in tests.
actor ActorBox<T> {
    private(set) var value: T
    init(_ initial: T) { self.value = initial }
    func set(_ newValue: T) { self.value = newValue }
}

// MARK: - Unencodable type

/// A type whose encoding always fails — used to test that encoding errors propagate.
struct UnencodableBody: Encodable, Sendable {
    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            self,
            .init(codingPath: [], debugDescription: "intentionally unencodable")
        )
    }
}

/// Returns a URLSessionConfiguration pre-wired to use MockURLProtocol.
func mockSessionConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    return config
}
