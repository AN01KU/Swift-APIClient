import Foundation

#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// Main API namespace containing all core types and protocols
public enum BaseAPI {

    // MARK: - Type Aliases

    public typealias APIResponse<T> = (data: T, response: HTTPURLResponse)

    // MARK: - MultipartFormData

    /// Builds a `multipart/form-data` request body.
    ///
    /// Create an instance, call `append` for each field or file, then pass it to
    /// `RequestBuilder.body(multipart:)`.
    ///
    /// ```swift
    /// try await client
    ///     .request(UploadEndpoint.profile)
    ///     .method(.post)
    ///     .body(multipart: { form in
    ///         form.append(nameData, name: "username")
    ///         try form.append(fileURL: avatarURL, name: "avatar")
    ///     })
    ///     .responseURL()
    /// ```
    public final class MultipartFormData: @unchecked Sendable {

        // MARK: - Internal part representation

        private enum PartSource {
            case data(Data)
            case stream(InputStream, length: UInt64)
        }

        private struct Part {
            let source: PartSource
            let headers: [String: String]
        }

        // MARK: - Properties

        /// The boundary string separating parts. Generated at init; stable for the lifetime of this object.
        public let boundary: String
        private var parts: [Part] = []

        // MARK: - Init

        public init(boundary: String = "Boundary-\(UUID().uuidString)") {
            self.boundary = boundary
        }

        // MARK: - Append: in-memory Data

        /// Append a plain text or binary field from in-memory data.
        ///
        /// - Parameters:
        ///   - data:     The field value as raw bytes.
        ///   - name:     The form field name (`Content-Disposition: form-data; name="…"`).
        ///   - fileName: Optional filename for the `Content-Disposition` header. Supply this for file uploads.
        ///   - mimeType: Optional MIME type. Omit for plain text fields.
        public func append(
            _ data: Data,
            name: String,
            fileName: String? = nil,
            mimeType: String? = nil
        ) {
            parts.append(Part(source: .data(data), headers: contentHeaders(name: name, fileName: fileName, mimeType: mimeType)))
        }

        // MARK: - Append: file URL

        /// Append a file from disk. MIME type is inferred from the file extension.
        ///
        /// - Parameters:
        ///   - fileURL: URL to an existing file on disk.
        ///   - name:    The form field name.
        /// - Throws: `APIError.encodingFailed` if the file cannot be read.
        public func append(fileURL: URL, name: String) throws {
            let fileName = fileURL.lastPathComponent
            let mimeType = Self.mimeType(for: fileURL.pathExtension)
            let data = try readFile(at: fileURL)
            parts.append(Part(source: .data(data), headers: contentHeaders(name: name, fileName: fileName, mimeType: mimeType)))
        }

        /// Append a file from disk with an explicit filename and MIME type.
        ///
        /// - Parameters:
        ///   - fileURL:  URL to an existing file on disk.
        ///   - name:     The form field name.
        ///   - fileName: The filename to report in `Content-Disposition`.
        ///   - mimeType: The explicit MIME type.
        /// - Throws: `APIError.encodingFailed` if the file cannot be read.
        public func append(fileURL: URL, name: String, fileName: String, mimeType: String) throws {
            let data = try readFile(at: fileURL)
            parts.append(Part(source: .data(data), headers: contentHeaders(name: name, fileName: fileName, mimeType: mimeType)))
        }

        // MARK: - Append: InputStream

        /// Append data from an `InputStream` with an explicit length.
        ///
        /// - Parameters:
        ///   - stream:   An open-able `InputStream`. The stream is opened and drained during ``encode()``.
        ///   - length:   The exact number of bytes the stream will produce.
        ///   - name:     The form field name.
        ///   - fileName: The filename for `Content-Disposition`.
        ///   - mimeType: The MIME type.
        public func append(
            _ stream: InputStream,
            length: UInt64,
            name: String,
            fileName: String,
            mimeType: String
        ) {
            parts.append(Part(source: .stream(stream, length: length), headers: contentHeaders(name: name, fileName: fileName, mimeType: mimeType)))
        }

        // MARK: - Encoding

        /// Encode all appended parts into a `(body: Data, contentType: String)` tuple.
        ///
        /// The returned `contentType` is `"multipart/form-data; boundary=<boundary>"` and must be
        /// set as the `Content-Type` header on the outgoing request.
        ///
        /// - Throws: `APIError.encodingFailed` if any stream cannot be drained.
        public func encode() throws -> (body: Data, contentType: String) {
            var body = Data()
            for part in parts {
                body.appendString("--\(boundary)\r\n")
                for (key, value) in part.headers.sorted(by: { $0.key < $1.key }) {
                    body.appendString("\(key): \(value)\r\n")
                }
                body.appendString("\r\n")
                switch part.source {
                case .data(let data):
                    body.append(data)
                case .stream(let stream, let length):
                    body.append(try drain(stream: stream, length: length))
                }
                body.appendString("\r\n")
            }
            body.appendString("--\(boundary)--\r\n")
            return (body, "multipart/form-data; boundary=\(boundary)")
        }

        // MARK: - Private helpers

        private func contentHeaders(name: String, fileName: String?, mimeType: String?) -> [String: String] {
            var disposition = "form-data; name=\"\(name)\""
            if let fileName { disposition += "; filename=\"\(fileName)\"" }
            var headers = ["Content-Disposition": disposition]
            if let mimeType { headers["Content-Type"] = mimeType }
            return headers
        }

        private func readFile(at url: URL) throws -> Data {
            do {
                return try Data(contentsOf: url)
            } catch {
                throw APIError.encodingFailed
            }
        }

        private func drain(stream: InputStream, length: UInt64) throws -> Data {
            stream.open()
            defer { stream.close() }
            var result = Data()
            result.reserveCapacity(Int(length))
            let bufferSize = 65_536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: bufferSize)
                guard count > 0 else {
                    if count < 0 { throw APIError.encodingFailed }
                    break
                }
                result.append(buffer, count: count)
            }
            return result
        }

        static func mimeType(for pathExtension: String) -> String {
            guard !pathExtension.isEmpty else { return "application/octet-stream" }
            #if canImport(UniformTypeIdentifiers)
                if let utType = UTType(filenameExtension: pathExtension),
                    let mime = utType.preferredMIMEType
                {
                    return mime
                }
            #endif
            return "application/octet-stream"
        }
    }

    // MARK: - EmptyResponse

    /// Empty response type for requests that don't return data
    public struct EmptyResponse: Codable, Sendable {
        public init() {}
    }
}
