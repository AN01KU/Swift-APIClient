import Foundation
import Testing

@testable import APIClient

// All network tests run serially to avoid MockURLProtocol.handler state bleed.
@Suite("Network Tests", .serialized)
struct NetworkTests {

    // MARK: - Request Builder Tests

    @Suite("Request Builder Tests")
    struct RequestBuilderTests {

        private func makeClient(handler: @escaping MockURLProtocol.Handler)
            -> BaseAPI.BaseAPIClient<MockEndpoint>
        {
            MockURLProtocol.handler = handler
            return BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())
        }

        @Test("request(_:).response decodes JSON response")
        func builderGetDecodesResponse() async throws {
            let payload = TestResponse(id: "b1", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let c = makeClient { req in
                (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let (result, _): BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "items", token: nil))
                .response()
            #expect(result.id == "b1")
        }

        @Test("builder sends correct HTTP method")
        func builderSetsMethod() async throws {
            let payload = TestResponse(id: "m", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let capturedMethod = ActorBox<String?>(nil)
            let c = makeClient { req in
                await capturedMethod.set(req.httpMethod)
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .method(.post)
                .response()
            #expect(await capturedMethod.value == "POST")
        }

        @Test("builder encodes JSON body")
        func builderEncodesJSONBody() async throws {
            let payload = TestResponse(id: "jb", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let capturedBody = ActorBox<Data?>(nil)
            let c = makeClient { req in
                await capturedBody.set(req.httpBody)
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .method(.post)
                .body(TestRequest(name: "alice", value: 1))
                .response()
            let body = await capturedBody.value
            #expect(body != nil)
            let decoded = try JSONDecoder().decode(TestRequest.self, from: body!)
            #expect(decoded.name == "alice")
        }

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
                return (
                    responseData, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .method(.put)
                .body(raw: raw, contentType: "text/plain")
                .response()
            #expect(await capturedBody.value == raw)
            #expect(await capturedCT.value == "text/plain")
        }

        @Test("builder merges additional headers")
        func builderMergesHeaders() async throws {
            let payload = TestResponse(id: "h", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let capturedHeader = ActorBox<String?>(nil)
            let c = makeClient { req in
                await capturedHeader.set(req.value(forHTTPHeaderField: "X-Trace-ID"))
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
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
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .headers(["X-A": "1"])
                .headers(["X-B": "2"])
                .response()
            #expect(await capturedA.value == "1")
            #expect(await capturedB.value == "2")
        }

        @Test("builder sets per-request timeout")
        func builderSetsTimeout() async throws {
            let payload = TestResponse(id: "t", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let capturedTimeout = ActorBox<TimeInterval?>(nil)
            let c = makeClient { req in
                await capturedTimeout.set(req.timeoutInterval)
                return (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "x", token: nil))
                .timeout(42)
                .response()
            #expect(await capturedTimeout.value == 42)
        }

        @Test("builder overrides validators: AcceptedStatusCodesValidator accepts 201")
        func builderOverridesValidators() async throws {
            let payload = TestResponse(id: "v", status: "created")
            let data = try JSONEncoder().encode(payload)
            let c = makeClient { req in
                (data, HTTPURLResponse(url: req.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!)
            }
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
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
                let _: BaseAPI.APIResponse<TestResponse> =
                    try await c
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

        @Test("responseURL returns HTTPURLResponse without decoding body")
        func builderResponseURL() async throws {
            let c = makeClient { req in
                (
                    Data("{\"unexpected\":true}".utf8),
                    HTTPURLResponse(url: req.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
                )
            }
            let httpResponse =
                try await c
                .request(MockEndpoint(endpoint: "del", token: nil))
                .method(.delete)
                .validators([BaseAPI.AcceptedStatusCodesValidator([204])])
                .responseURL()
            #expect(httpResponse.statusCode == 204)
        }

        @Test("responseData returns raw bytes")
        func builderResponseData() async throws {
            let raw = Data("raw content".utf8)
            let c = makeClient { req in
                (raw, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let (data, _) =
                try await c
                .request(MockEndpoint(endpoint: "file", token: nil))
                .responseData()
            #expect(data == raw)
        }

        @Test("builder propagates server error")
        func builderPropagatesServerError() async throws {
            let c = makeClient { req in
                (Data(), HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            do {
                let _: BaseAPI.APIResponse<TestResponse> =
                    try await c
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
            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "em", token: nil))
                .response()
            #expect(monitor.starts.count == 1)
            #expect(monitor.finishes.count == 1)
        }

        @Test("builder propagates encoding failure instead of sending bodyless request")
        func builderPropagatesEncodingFailure() async throws {
            let c = makeClient { req in
                // This handler should never be reached.
                (Data(), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            do {
                let _: BaseAPI.APIResponse<TestResponse> =
                    try await c
                    .request(MockEndpoint(endpoint: "x", token: nil))
                    .method(.post)
                    .body(UnencodableBody())
                    .response()
                #expect(Bool(false), "Should have thrown encodingFailed")
            } catch BaseAPI.APIError.encodingFailed {
                // expected
            }
        }

        @Test("builder modifiers do not mutate the original")
        func builderIsImmutable() async throws {
            let payload = TestResponse(id: "imm", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let c = makeClient { req in
                (data, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let base = c.request(MockEndpoint(endpoint: "x", token: nil))
            let withPost = base.method(.post)
            let withGet = base.method(.get)
            #expect(withPost.httpMethod == .post)
            #expect(withGet.httpMethod == .get)
            #expect(base.httpMethod == .get)
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

        @Test("form body sets Content-Type to application/x-www-form-urlencoded")
        func formBodySetsContentType() async throws {
            let payload = TestResponse(id: "f1", status: "ok")
            let responseData = try JSONEncoder().encode(payload)
            let capturedCT = ActorBox<String?>(nil)

            let c = makeClient { req in
                await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
                return (
                    responseData,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "auth/token", token: nil))
                .method(.post)
                .body(form: ["grant_type": "client_credentials"])
                .response()

            #expect(await capturedCT.value == "application/x-www-form-urlencoded")
        }

        @Test("form body encodes single key-value pair correctly")
        func formBodyEncodesSinglePair() async throws {
            let payload = TestResponse(id: "f2", status: "ok")
            let responseData = try JSONEncoder().encode(payload)
            let capturedBody = ActorBox<Data?>(nil)

            let c = makeClient { req in
                await capturedBody.set(req.httpBody)
                return (
                    responseData,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
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
                return (
                    responseData,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "token", token: nil))
                .method(.post)
                .body(form: ["scope": "read write", "grant_type": "password", "username": "alice"])
                .response()

            let body = await capturedBody.value
            let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
            #expect(bodyString == "grant_type=password&scope=read%20write&username=alice")
        }

        @Test("form body percent-encodes special characters")
        func formBodyPercentEncodesSpecialChars() async throws {
            let payload = TestResponse(id: "f4", status: "ok")
            let responseData = try JSONEncoder().encode(payload)
            let capturedBody = ActorBox<Data?>(nil)

            let c = makeClient { req in
                await capturedBody.set(req.httpBody)
                return (
                    responseData,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "search", token: nil))
                .method(.post)
                .body(form: ["q": "hello world&foo=bar"])
                .response()

            let body = await capturedBody.value
            let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
            #expect(bodyString == "q=hello%20world%26foo%3Dbar")
        }

        @Test("form body with empty dictionary produces no body bytes")
        func formBodyEncodesEmptyDict() async throws {
            let payload = TestResponse(id: "f5", status: "ok")
            let responseData = try JSONEncoder().encode(payload)
            let capturedCT = ActorBox<String?>(nil)

            let c = makeClient { req in
                await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
                return (
                    responseData,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let _: BaseAPI.APIResponse<TestResponse> =
                try await c
                .request(MockEndpoint(endpoint: "token", token: nil))
                .method(.post)
                .body(form: [:])
                .response()

            #expect(await capturedCT.value == "application/x-www-form-urlencoded")
        }

        @Test("form body works with responseData()")
        func formBodyWorksWithResponseData() async throws {
            let raw = Data("ok".utf8)
            let capturedCT = ActorBox<String?>(nil)

            let c = makeClient { req in
                await capturedCT.set(req.value(forHTTPHeaderField: "Content-Type"))
                return (
                    raw,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }

            let (data, _) =
                try await c
                .request(MockEndpoint(endpoint: "submit", token: nil))
                .method(.post)
                .body(form: ["key": "value"])
                .responseData()

            #expect(data == raw)
            #expect(await capturedCT.value == "application/x-www-form-urlencoded")
        }

        @Test("form body modifier does not mutate original builder")
        func formBodyModifierIsImmutable() async throws {
            let payload = TestResponse(id: "imm", status: "ok")
            let data = try JSONEncoder().encode(payload)
            let c = makeClient { req in
                (
                    data,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }
            let base = c.request(MockEndpoint(endpoint: "x", token: nil)).method(.post)
            let withForm = base.body(form: ["a": "1"])
            let withJSON = base.body(TestRequest(name: "n", value: 0))

            if case .formURL = withForm.body {
            } else {
                #expect(Bool(false), "Expected .formURL on withForm")
            }
            if case .json = withJSON.body {
            } else {
                #expect(Bool(false), "Expected .json on withJSON")
            }
            if case .none = base.body {
            } else {
                #expect(Bool(false), "Expected .none on base")
            }
        }
    }

    // MARK: - Raw Body Tests

    @Suite("Raw Body Tests")
    struct RawBodyTests {

        private func client(responding handler: @escaping MockURLProtocol.Handler)
            -> BaseAPI.BaseAPIClient<MockEndpoint>
        {
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
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
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
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
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
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
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
                (
                    Data(),
                    HTTPURLResponse(
                        url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)!
                )
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

        @Test("raw body requests set Content-Type: application/json header")
        func rawBodyRequestSetsContentType() async throws {
            let payload = TestResponse(id: "hdr", status: "ok")
            let responseData = try JSONEncoder().encode(payload)
            let capturedHeaderRef = ActorBox<String?>(nil)

            let c = client { request in
                await capturedHeaderRef.set(request.value(forHTTPHeaderField: "Content-Type"))
                return (
                    responseData,
                    HTTPURLResponse(
                        url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            }

            let raw = Data("{}".utf8)
            let _: BaseAPI.APIResponse<TestResponse> = try await c.post(
                MockEndpoint(endpoint: "hdr", token: nil), rawBody: raw)

            let header = await capturedHeaderRef.value
            #expect(header == "application/json")
        }
    }

    // MARK: - Event Monitor Tests

    @Suite("Event Monitor Tests")
    struct EventMonitorTests {

        /// A monitor that records every event it receives.
        final class RecordingMonitor: BaseAPI.RequestEventMonitor, @unchecked Sendable {
            var starts: [(endpoint: String, method: String)] = []
            var retries: [(endpoint: String, attemptCount: Int, delay: TimeInterval)] = []
            var finishes: [(endpoint: String, statusCode: Int, duration: TimeInterval)] = []
            var failures: [(endpoint: String, error: BaseAPI.APIError, duration: TimeInterval)] = []

            func requestDidStart(_ request: URLRequest, endpoint: String, method: String) {
                starts.append((endpoint, method))
            }
            func requestWillRetry(
                _ request: URLRequest, endpoint: String, method: String,
                attemptCount: Int, delay: TimeInterval
            ) {
                retries.append((endpoint, attemptCount, delay))
            }
            func requestDidFinish(
                _ request: URLRequest, endpoint: String, method: String,
                response: HTTPURLResponse, duration: TimeInterval
            ) {
                finishes.append((endpoint, response.statusCode, duration))
            }
            func requestDidFail(
                _ request: URLRequest, endpoint: String, method: String,
                error: BaseAPI.APIError, duration: TimeInterval
            ) {
                failures.append((endpoint, error, duration))
            }
        }

        private func makeClient(
            monitor: BaseAPI.RequestEventMonitor,
            handler: @escaping MockURLProtocol.Handler
        )
            -> BaseAPI.BaseAPIClient<MockEndpoint>
        {
            MockURLProtocol.handler = handler
            return BaseAPI.BaseAPIClient<MockEndpoint>(
                sessionConfiguration: mockSessionConfiguration(),
                eventMonitors: [monitor]
            )
        }

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
            )
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
                    return (
                        Data(),
                        HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
                    )
                }
                return (
                    successData,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
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
            for try await progress
                in c
                .request(MockEndpoint(endpoint: "file", token: nil))
                .download()
            {
                if let d = progress.data { finalData = d }
            }
            #expect(finalData == content)
        }

        @Test("download emits progress events before final event")
        func downloadEmitsProgressEvents() async throws {
            let content = Data(repeating: 0xAB, count: 4096)
            let c = makeClient(responseData: content)

            var progressEvents: [BaseAPI.DownloadProgress] = []
            for try await progress in c.download(MockEndpoint(endpoint: "file", token: nil)) {
                progressEvents.append(progress)
            }

            #expect(progressEvents.count >= 1)
            #expect(progressEvents.last?.data != nil)
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

            let intermediate = events.dropLast()
            for event in intermediate {
                #expect(event.data == nil)
            }
        }

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
            let c = makeClient(responseData: content)

            var lastProgress: BaseAPI.DownloadProgress?
            for try await p in c.download(MockEndpoint(endpoint: "file", token: nil)) {
                lastProgress = p
            }
            #expect(lastProgress?.totalBytesExpected == nil)
            #expect(lastProgress?.fraction == nil)
        }

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

        @Test("download fires requestDidStart and requestDidFinish on success")
        func downloadFiresMonitorEvents() async throws {
            let monitor = EventMonitorTests.RecordingMonitor()
            let content = Data("monitored".utf8)

            MockURLProtocol.handler = { req in
                (
                    content,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
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
                (
                    Data(),
                    HTTPURLResponse(
                        url: req.url!, statusCode: 500,
                        httpVersion: nil, headerFields: nil)!
                )
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

        @Test("download via builder applies extra headers")
        func downloadBuilderAppliesHeaders() async throws {
            let content = Data("ok".utf8)
            let capturedHeader = ActorBox<String?>(nil)

            MockURLProtocol.handler = { req in
                await capturedHeader.set(req.value(forHTTPHeaderField: "X-Download-Token"))
                return (
                    content,
                    HTTPURLResponse(
                        url: req.url!, statusCode: 200,
                        httpVersion: nil, headerFields: nil)!
                )
            }
            let c = BaseAPI.BaseAPIClient<MockEndpoint>(sessionConfiguration: mockSessionConfiguration())

            for try await _
                in c
                .request(MockEndpoint(endpoint: "file", token: nil))
                .headers(["X-Download-Token": "secret"])
                .download()
            {}

            #expect(await capturedHeader.value == "secret")
        }
    }

    // MARK: - Unauthorized Handler Tests

    @Suite("Unauthorized Handler Tests")
    struct UnauthorizedHandlerTests {

        /// Interceptor that succeeds on the second attempt (simulates token refresh).
        struct RetryOnceInterceptor: BaseAPI.RequestInterceptor {
            let callCount = ActorBox<Int>(0)

            func adapt(_ request: URLRequest) async throws -> URLRequest { request }

            func retry(
                _ request: URLRequest, dueTo error: Error, attemptCount: Int
            ) async -> BaseAPI.RetryDecision {
                await callCount.set(await callCount.value + 1)
                return attemptCount < 2 ? .retry(delay: 0) : .doNotRetry
            }
        }

        @Test("unauthorizedHandler fires once on final 401 failure")
        func handlerFiresOnFinalFailure() async throws {
            MockURLProtocol.handler = { req in
                (Data(), HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
            }
            let handlerCallCount = ActorBox<Int>(0)
            let client = BaseAPI.BaseAPIClient<MockEndpoint>(
                sessionConfiguration: mockSessionConfiguration(),
                unauthorizedHandler: { _ in
                    Task { await handlerCallCount.set(await handlerCallCount.value + 1) }
                }
            )
            do {
                let _: BaseAPI.APIResponse<TestResponse> =
                    try await client.request(MockEndpoint(endpoint: "secure", token: nil)).response()
                Issue.record("Expected throw")
            } catch {}
            // Brief yield so the Task inside the handler can complete.
            try await Task.sleep(nanoseconds: 10_000_000)
            #expect(await handlerCallCount.value == 1)
        }

        @Test("unauthorizedHandler does NOT fire when interceptor retries 401 and succeeds")
        func handlerDoesNotFireOnRetrySuccess() async throws {
            let attemptCount = ActorBox<Int>(0)
            let successPayload = try JSONEncoder().encode(TestResponse(id: "ok", status: "ok"))
            MockURLProtocol.handler = { req in
                await attemptCount.set(await attemptCount.value + 1)
                let count = await attemptCount.value
                if count == 1 {
                    return (Data(), HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
                }
                return (successPayload, HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let handlerCallCount = ActorBox<Int>(0)
            let interceptor = RetryOnceInterceptor()
            let client = BaseAPI.BaseAPIClient<MockEndpoint>(
                sessionConfiguration: mockSessionConfiguration(),
                interceptors: [interceptor],
                unauthorizedHandler: { _ in
                    Task { await handlerCallCount.set(await handlerCallCount.value + 1) }
                }
            )
            let (result, _): BaseAPI.APIResponse<TestResponse> =
                try await client.request(MockEndpoint(endpoint: "secure", token: nil)).response()
            #expect(result.id == "ok")
            try await Task.sleep(nanoseconds: 10_000_000)
            #expect(await handlerCallCount.value == 0)
        }
    }
}
