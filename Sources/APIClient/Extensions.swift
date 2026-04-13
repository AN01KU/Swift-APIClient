import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

// MARK: - URLRequest Extensions

extension URLRequest {

    mutating func addJSONHeaders(additionalHeaders: [String: String] = [:]) {
        setValue("application/json", forHTTPHeaderField: "Accept")
        for (key, value) in additionalHeaders {
            setValue(value, forHTTPHeaderField: key)
        }
    }

    mutating func addJSONBody<T: Encodable>(_ body: T?, encoder: JSONEncoder) throws {
        guard let body = body else { return }
        do {
            httpBody = try encoder.encode(body)
        } catch {
            throw BaseAPI.APIError.encodingFailed
        }
    }

    mutating func addMultipartData(data: BaseAPI.MultipartData) throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        timeoutInterval = 60
        cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            httpBody = try createMultipartBody(data: data, boundary: boundary)
        } catch {
            throw BaseAPI.APIError.encodingFailed
        }
    }

    private func createMultipartBody(
        data: BaseAPI.MultipartData,
        boundary: String
    ) throws -> Data {
        var body = Data()

        // Add parameters
        if let parameters = data.parameters {
            for (key, value) in parameters {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
        }

        // Add files
        if let fileURLs = data.fileURLs {
            for fileURL in fileURLs {
                let filename = fileURL.lastPathComponent
                let fileData = try Data(contentsOf: fileURL)
                let mimeType = URLSession.mimeTypeForPath(fileURL.pathExtension)

                body.appendString("--\(boundary)\r\n")
                body.appendString(
                    "Content-Disposition: form-data; name=\"\(data.fileKeyName)\"; filename=\"\(filename)\"\r\n"
                )
                body.appendString("Content-Type: \(mimeType)\r\n\r\n")
                body.append(fileData)
                body.appendString("\r\n")
            }
        }

        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

// MARK: - Data Extensions

extension Data {

    mutating func appendString(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
        append(data)
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        decoder: JSONDecoder,
        endpoint: String = "",
        method: String = ""
    ) throws -> T {
        if isEmpty, T.self == BaseAPI.EmptyResponse.self {
            return BaseAPI.EmptyResponse() as! T
        }
        return try decoder.decode(type, from: self)
    }
}

// MARK: - Form URL Encoding

extension Dictionary where Key == String, Value == String {
    /// Percent-encodes the dictionary as `application/x-www-form-urlencoded`.
    ///
    /// Keys and values are encoded with `urlQueryAllowed` minus `+`, `&`, `=` — the
    /// subset safe inside a query string component per RFC 3986. Pairs are sorted
    /// alphabetically by key for deterministic output (useful in tests and caches).
    func formURLEncoded() -> Data {
        // Characters allowed in query components minus delimiters that have special meaning
        // inside `key=value&key=value` strings.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "+&=")

        let pairs =
            self
            .sorted { $0.key < $1.key }
            .compactMap { key, value -> String? in
                guard
                    let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed),
                    let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed)
                else { return nil }
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        return Data(pairs.utf8)
    }
}

// MARK: - AnyEncodable

/// Type-erasing wrapper that lets `JSONEncoder` encode an `any Encodable` value.
struct AnyEncodable: Encodable {
    private let encodeBody: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        self.encodeBody = { try value.encode(to: $0) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeBody(encoder)
    }
}

// MARK: - URLSession Extensions

extension URLSession {
    class func mimeTypeForPath(_ pathExtension: String) -> String {
        #if canImport(UniformTypeIdentifiers)
            if let utType = UTType(filenameExtension: pathExtension),
                let mimeType = utType.preferredMIMEType
            {
                return mimeType
            }
        #endif
        return "application/octet-stream"
    }
}
