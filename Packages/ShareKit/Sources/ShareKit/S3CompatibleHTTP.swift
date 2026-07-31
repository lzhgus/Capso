import CryptoKit
import Foundation

/// Shared SigV4 + URLSession transport for Amazon S3 and S3-compatible stores (R2).
///
/// Wire format:
/// - SigV4 with the real payload SHA-256 (not `UNSIGNED-PAYLOAD`)
/// - signed headers: `content-type;host;x-amz-content-sha256;x-amz-date`
/// - Amazon virtual-hosted vs custom path-style endpoints (scheme preserved)
/// - R2 path-style on `<accountId>.r2.cloudflarestorage.com` with region `auto`
///
/// Uploads hash the file in chunks, then use `URLSession.upload(fromFile:)` so
/// recordings are not held as one `Data` buffer.
enum S3CompatibleHTTP {
    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    struct Target: Sendable, Equatable {
        /// `http` or `https` — preserved from custom endpoints so LAN MinIO works.
        let scheme: String
        /// Host plus optional port only (no path).
        let host: String
        let canonicalURI: String

        var requestURLString: String {
            "\(scheme)://\(host)\(canonicalURI)"
        }
    }

    /// Amazon S3 virtual-hosted addressing, or path-style for a custom endpoint.
    static func amazonS3Target(bucket: String, objectKey: String, region: String, endpoint: String?) -> Target {
        let encodedKey = ShareConfig.encodeObjectKey(objectKey)
        if let endpoint, let parsed = parseEndpoint(endpoint) {
            let canonicalURI = "\(parsed.pathPrefix)/\(bucket)/\(encodedKey)"
            return Target(scheme: parsed.scheme, host: parsed.host, canonicalURI: canonicalURI)
        }
        return Target(
            scheme: "https",
            host: "\(bucket).s3.\(region).amazonaws.com",
            canonicalURI: "/\(encodedKey)"
        )
    }

    /// Cloudflare R2 path-style addressing.
    static func r2Target(accountID: String, bucket: String, objectKey: String) -> Target {
        let encodedKey = ShareConfig.encodeObjectKey(objectKey)
        let normalizedAccountID = normalizeAccountID(accountID)
        return Target(
            scheme: "https",
            host: "\(normalizedAccountID).r2.cloudflarestorage.com",
            canonicalURI: "/\(bucket)/\(encodedKey)"
        )
    }

    static func putObject(
        file: URL,
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        contentType: String
    ) async throws {
        let (payloadHash, contentLength): (String, Int)
        do {
            (payloadHash, contentLength) = try sha256File(file)
        } catch {
            throw ShareError.unknown("Couldn't read file for upload: \(error.localizedDescription)")
        }

        let request = try signedPutRequest(
            target: target,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            payloadHash: payloadHash,
            contentLength: contentLength,
            contentType: contentType
        )

        do {
            let (body, response) = try await URLSession.shared.upload(for: request, fromFile: file)
            try validate(response: response, body: body)
        } catch let error as ShareError {
            throw error
        } catch {
            throw ShareError.network(underlying: error.localizedDescription)
        }
    }

    static func deleteObject(
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String
    ) async throws {
        let request = try signedDeleteRequest(
            target: target,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey
        )
        do {
            let (body, response) = try await URLSession.shared.data(for: request)
            try validate(response: response, body: body)
        } catch let error as ShareError {
            throw error
        } catch {
            throw ShareError.network(underlying: error.localizedDescription)
        }
    }

    /// Empty-body DELETE SigV4 request (AWS empty-payload hash).
    static func signedDeleteRequest(
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        now: Date = Date()
    ) throws -> URLRequest {
        try signedRequest(
            method: "DELETE",
            target: target,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            contentType: nil,
            contentSHA256: emptyPayloadHash,
            contentLength: nil,
            now: now
        )
    }

    static func signedPutRequest(
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        payloadHash: String,
        contentLength: Int,
        contentType: String,
        now: Date = Date()
    ) throws -> URLRequest {
        var request = try signedRequest(
            method: "PUT",
            target: target,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            contentType: contentType,
            contentSHA256: payloadHash,
            contentLength: contentLength,
            now: now
        )
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        return request
    }

    /// Convenience for tests — hash `payload` then sign.
    static func signedPutRequest(
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        payload: Data,
        contentType: String,
        now: Date = Date()
    ) throws -> URLRequest {
        try signedPutRequest(
            target: target,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            payloadHash: sha256Hex(payload),
            contentLength: payload.count,
            contentType: contentType,
            now: now
        )
    }

    static func mapResponseError(statusCode: Int, body: Data) -> ShareError {
        let text = String(data: body, encoding: .utf8) ?? ""
        if let code = xmlTag(text, "Code") {
            switch code {
            case "InvalidAccessKeyId", "SignatureDoesNotMatch", "AccessDenied", "InvalidToken":
                return .invalidCredentials
            case "QuotaExceeded", "EntityTooLarge":
                return .quotaExceeded
            case "NoSuchBucket":
                return .unknown("Bucket not found — verify the bucket name in Cloud Share settings")
            default:
                let message = xmlTag(text, "Message") ?? text
                return .unknown("\(code): \(message)")
            }
        }

        switch statusCode {
        case 401, 403:
            return .invalidCredentials
        case 413, 507:
            return .quotaExceeded
        default:
            return .unknown(text.isEmpty ? "HTTP \(statusCode)" : "HTTP \(statusCode): \(text)")
        }
    }

    // MARK: - Endpoint helpers

    struct ParsedEndpoint: Equatable {
        let scheme: String
        let host: String
        /// Empty or `"/" + encoded segments`, no trailing slash.
        let pathPrefix: String
    }

    /// Parses a user-supplied endpoint into scheme, host[:port], and optional path prefix.
    static func parseEndpoint(_ raw: String) -> ParsedEndpoint? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let scheme: String
        if value.lowercased().hasPrefix("https://") {
            scheme = "https"
            value.removeFirst("https://".count)
        } else if value.lowercased().hasPrefix("http://") {
            scheme = "http"
            value.removeFirst("http://".count)
        } else {
            scheme = "https"
        }

        while value.hasSuffix("/") {
            value.removeLast()
        }
        guard !value.isEmpty else { return nil }

        let parts = value.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = String(parts[0])
        guard !host.isEmpty, !host.contains(" ") else { return nil }

        let pathPrefix: String
        if parts.count > 1 {
            let encoded = ShareConfig.encodeObjectKey(String(parts[1]))
            pathPrefix = encoded.isEmpty ? "" : "/\(encoded)"
        } else {
            pathPrefix = ""
        }

        return ParsedEndpoint(scheme: scheme, host: host, pathPrefix: pathPrefix)
    }

    static func normalizeAccountID(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.lowercased().hasPrefix("https://") {
            value.removeFirst("https://".count)
        } else if value.lowercased().hasPrefix("http://") {
            value.removeFirst("http://".count)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if let range = value.range(of: ".r2.cloudflarestorage.com") {
            value = String(value[value.startIndex..<range.lowerBound])
        }
        return value
    }

    // MARK: - Signing

    static func signedRequest(
        method: String,
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        contentType: String?,
        contentSHA256: String,
        contentLength: Int?,
        now: Date = Date()
    ) throws -> URLRequest {
        guard let url = URL(string: target.requestURLString) else {
            throw ShareError.unknown("Invalid S3 endpoint URL")
        }

        let (amzDate, dateStamp) = timestamps(now)
        let service = "s3"
        let host = target.host

        let canonicalHeaders: String
        let signedHeaders: String
        if let contentType {
            canonicalHeaders =
                "content-type:\(contentType)\n" +
                "host:\(host)\n" +
                "x-amz-content-sha256:\(contentSHA256)\n" +
                "x-amz-date:\(amzDate)\n"
            signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        } else {
            canonicalHeaders =
                "host:\(host)\n" +
                "x-amz-content-sha256:\(contentSHA256)\n" +
                "x-amz-date:\(amzDate)\n"
            signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        }

        let canonicalRequest = [
            method,
            target.canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            contentSHA256,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/\(service)/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        let kDate = hmacSHA256(key: Data("AWS4\(secretAccessKey)".utf8), message: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, message: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, message: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, message: Data("aws4_request".utf8))
        let signature = ShareSigning.hex(hmacSHA256(key: kSigning, message: Data(stringToSign.utf8)))

        let authorization = "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKeyId)/\(scope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(contentSHA256, forHTTPHeaderField: "X-Amz-Content-Sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let contentLength {
            request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        }
        return request
    }

    private static func validate(response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ShareError.network(underlying: "Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapResponseError(statusCode: http.statusCode, body: body)
        }
    }

    /// Chunked file digest used by `putObject` — must match `SHA256(Data(contentsOf:))`.
    static func sha256File(_ file: URL) throws -> (hash: String, size: Int) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }

        var hasher = SHA256()
        var size = 0
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            size += chunk.count
            hasher.update(data: chunk)
        }
        return (ShareSigning.hex(Data(hasher.finalize())), size)
    }

    private static func timestamps(_ date: Date) -> (amz: String, stamp: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amz = formatter.string(from: date)
        formatter.dateFormat = "yyyyMMdd"
        let stamp = formatter.string(from: date)
        return (amz, stamp)
    }

    private static func hmacSHA256(key: Data, message: Data) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
    }

    private static func sha256Hex(_ data: Data) -> String {
        ShareSigning.hex(Data(SHA256.hash(data: data)))
    }

    private static func xmlTag(_ xml: String, _ tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>"),
              start.upperBound <= end.lowerBound else {
            return nil
        }
        let value = String(xml[start.upperBound..<end.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
