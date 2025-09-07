import Foundation
import UniformTypeIdentifiers

// MARK: - URLRequest Extensions

extension URLRequest {

    mutating func addJSONHeaders(authHeader: [String: String]) {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
        headers.merge(authHeader) { _, new in new }

        for (key, value) in headers {
            setValue(value, forHTTPHeaderField: key)
        }
    }

    mutating func addJSONBody<T: Encodable>(
        _ body: T?,
        encoder: JSONEncoder,
        printRequestBody: Bool = false,
        logger: BaseAPI.APIClientLoggingProtocol?,
        endpoint: String,
        method: String
    ) throws {
        guard let body = body else { return }

        do {
            let payload = try encoder.encode(body)
            httpBody = payload

            if printRequestBody {
                if let decodedString = String(data: payload, encoding: .utf8) {
                    logger?.info("\(method):\(endpoint) REQUEST | body string: \(decodedString)")
                }
            }
        } catch {
            throw BaseAPI.APIError.encodingFailed
        }
    }

    mutating func addMultipartData(
        data: BaseAPI.MultipartData,
        printRequestBody: Bool = false,
        logger: BaseAPI.APIClientLoggingProtocol?,
        endpoint: String,
        method: String
    ) throws {
        let boundary = "Boundary-\(UUID().uuidString)"

        setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        timeoutInterval = 60
        cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        do {
            httpBody = try createMultipartBody(data: data, boundary: boundary)
            if printRequestBody {
                let stringValue = data.stringValue
                logger?.info("\(method):\(endpoint) REQUEST | body string: \(stringValue)")
            }
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
        printResponseBody: Bool = false,
        logger: BaseAPI.APIClientLoggingProtocol? = nil,
        endpoint: String = "",
        method: String = ""
    ) throws -> T {
        // Handle empty response
        if isEmpty {
            if T.self == BaseAPI.EmptyResponse.self {
                return BaseAPI.EmptyResponse() as! T
            }
        }

        if printResponseBody {
            if let decodedString = String(data: self, encoding: .utf8) {
                logger?.info(
                    "\(method):\(endpoint) REQUEST | responseData string: \(decodedString)")
            }
        }

        return try decoder.decode(type, from: self)
    }
}

// MARK: - URLSession Extensions

extension URLSession {
    class func mimeTypeForPath(_ pathExtension: String) -> String {
        if let utType = UTType(filenameExtension: pathExtension),
            let mimeType = utType.preferredMIMEType
        {
            return mimeType
        }
        return "application/octet-stream"
    }
}
