import Foundation

extension BaseAPI {

    // MARK: - RequestBody

    /// Represents the body of an HTTP request.
    public enum RequestBody: @unchecked Sendable {
        /// Encode the value as JSON using the client's `JSONEncoder`.
        case json(any Encodable)
        /// Percent-encode key/value pairs as `application/x-www-form-urlencoded`.
        case formURL([String: String])
        /// Send raw bytes as-is (e.g. pre-serialized JSON, binary payloads).
        case raw(Data, contentType: String = "application/json")
        /// Multipart form-data upload.
        case multipart(MultipartFormData)
        /// No body.
        case none

        // Equatable conformance is intentionally omitted — `Encodable` is not `Equatable`.
    }

    // MARK: - RequestBuilder

    /// Fluent builder for constructing and executing a single HTTP request.
    ///
    /// Obtain a builder from the client, customise it with chainable modifiers,
    /// then execute it with one of the terminal methods:
    ///
    /// ```swift
    /// // GET with a decoded response
    /// let (user, _): BaseAPI.APIResponse<User> = try await client
    ///     .request(UsersEndpoint.profile(id: 42))
    ///     .response(User.self)
    ///
    /// // POST with a JSON body, custom timeout, extra headers
    /// let httpResponse = try await client
    ///     .request(UsersEndpoint.create)
    ///     .method(.post)
    ///     .body(CreateUserRequest(name: "Alice"))
    ///     .headers(["X-Request-ID": UUID().uuidString])
    ///     .timeout(30)
    ///     .responseURL()
    ///
    /// // Use a custom validator just for this request
    /// let (raw, _) = try await client
    ///     .request(FilesEndpoint.download(id: "abc"))
    ///     .validators([BaseAPI.AcceptedStatusCodesValidator([200, 304])])
    ///     .responseData()
    /// ```
    ///
    /// Modifiers that aren't called fall back to the client's defaults
    /// (method `.get`, no extra headers, client-level validators, client timeout).
    public struct RequestBuilder<Endpoint: APIEndpoint>: Sendable {

        // MARK: - Stored configuration

        let endpoint: Endpoint
        let client: BaseAPIClient<Endpoint>

        var httpMethod: BaseAPI.HTTPMethod = .get
        var additionalHeaders: [String: String] = [:]
        var additionalQueryParameters: [String: String] = [:]
        var body: RequestBody = .none
        var timeoutInterval: TimeInterval? = nil
        var cachePolicy: URLRequest.CachePolicy? = nil
        /// When non-nil these validators replace (not merge) the client-level validators.
        var overrideValidators: [any ResponseValidator]? = nil

        // MARK: - Fluent modifiers

        /// Set the HTTP method. Defaults to `.get`.
        public func method(_ method: BaseAPI.HTTPMethod) -> Self {
            var copy = self
            copy.httpMethod = method
            return copy
        }

        /// Merge additional headers into the request.
        /// These are applied after the endpoint's own headers and after interceptors,
        /// so they take highest precedence.
        public func headers(_ headers: [String: String]) -> Self {
            var copy = self
            copy.additionalHeaders = self.additionalHeaders.merging(headers) { _, new in new }
            return copy
        }

        /// Merge additional query parameters into the request URL.
        /// These are merged with the endpoint's own `queryParameters`; call-site values win on conflict.
        public func queryParameters(_ params: [String: String]) -> Self {
            var copy = self
            copy.additionalQueryParameters = self.additionalQueryParameters.merging(params) { _, new in new }
            return copy
        }

        /// Set the request body to a JSON-encodable value.
        public func body<T: Encodable>(_ value: T) -> Self {
            var copy = self
            copy.body = .json(value)
            return copy
        }

        /// Set the request body to raw bytes with an explicit Content-Type.
        public func body(raw data: Data, contentType: String = "application/json") -> Self {
            var copy = self
            copy.body = .raw(data, contentType: contentType)
            return copy
        }

        /// Set the request body to `application/x-www-form-urlencoded`.
        ///
        /// Keys and values are percent-encoded per RFC 3986. Use this for OAuth token
        /// endpoints, legacy form-based APIs, or any endpoint that rejects JSON bodies.
        ///
        /// ```swift
        /// try await client
        ///     .request(AuthEndpoint.token)
        ///     .method(.post)
        ///     .body(form: ["grant_type": "client_credentials", "scope": "read write"])
        ///     .response(TokenResponse.self)
        /// ```
        public func body(form fields: [String: String]) -> Self {
            var copy = self
            copy.body = .formURL(fields)
            return copy
        }

        /// Set the request body to multipart form-data.
        ///
        /// The closure receives a ``BaseAPI/MultipartFormData`` instance. Append all fields
        /// and files before the closure returns.
        ///
        /// ```swift
        /// .body(multipart: { form in
        ///     form.append(nameData, name: "username")
        ///     try form.append(fileURL: avatarURL, name: "avatar")
        /// })
        /// ```
        public func body(multipart configure: (MultipartFormData) throws -> Void) rethrows -> Self {
            let form = MultipartFormData()
            try configure(form)
            var copy = self
            copy.body = .multipart(form)
            return copy
        }

        /// Override the timeout for this request only (seconds).
        public func timeout(_ seconds: TimeInterval) -> Self {
            var copy = self
            copy.timeoutInterval = seconds
            return copy
        }

        /// Override the cache policy for this request only.
        public func cachePolicy(_ policy: URLRequest.CachePolicy) -> Self {
            var copy = self
            copy.cachePolicy = policy
            return copy
        }

        /// Replace the client-level validators with a custom set for this request only.
        public func validators(_ validators: [any ResponseValidator]) -> Self {
            var copy = self
            copy.overrideValidators = validators
            return copy
        }

        // MARK: - Terminal methods

        /// Execute the request and decode the response body.
        ///
        /// - Returns: `(data: Response, response: HTTPURLResponse)`
        public func response<Response: Decodable>(_ type: Response.Type = Response.self)
            async throws -> APIResponse<Response>
        {
            try await client.execute(self)
        }

        /// Execute the request and return only the `HTTPURLResponse` (ignoring the body).
        public func responseURL() async throws -> HTTPURLResponse {
            let result: APIResponse<EmptyResponse> = try await client.execute(self)
            return result.response
        }

        /// Execute the request and return the raw response body as `Data`.
        public func responseData() async throws -> APIResponse<Data> {
            try await client.executeRaw(self)
        }

        /// Stream download progress for this request.
        ///
        /// Returns an `AsyncThrowingStream` that emits one ``DownloadProgress`` event per
        /// received chunk. The final event has a non-nil `data` property.
        ///
        /// ```swift
        /// for try await progress in client
        ///     .request(FileEndpoint.video("intro.mp4"))
        ///     .headers(["Authorization": "Bearer \(token)"])
        ///     .download()
        /// {
        ///     if let file = progress.data {
        ///         save(file)
        ///     } else {
        ///         print("\(Int((progress.fraction ?? 0) * 100))%")
        ///     }
        /// }
        /// ```
        public func download() -> AsyncThrowingStream<DownloadProgress, Error> {
            client.executeDownload(self)
        }
    }
}
