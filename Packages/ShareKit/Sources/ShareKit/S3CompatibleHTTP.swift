import CryptoKit
import Foundation

/// S3 / R2 transport ported from the working capcap uploader:
/// `AWSV4Signer` + `S3Common` + `R2Uploader` / `S3Uploader`.
///
/// Wire format matches that stack:
/// - SigV4 with the real payload SHA-256 (not `UNSIGNED-PAYLOAD`)
/// - signed headers: `content-type;host;x-amz-content-sha256;x-amz-date`
/// - Amazon virtual-hosted vs custom path-style endpoints
/// - R2 path-style on `<accountId>.r2.cloudflarestorage.com` with region `auto`
///
/// Capso only changes the body transport: hash the file in chunks, then
/// `URLSession.upload(fromFile:)` so recordings are not held as one `Data`.
enum S3CompatibleHTTP {
    static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    struct Target: Sendable {
        let host: String
        let canonicalURI: String
    }

    /// Mirrors capcap `S3Uploader` host / canonical URI selection.
    static func amazonS3Target(bucket: String, objectKey: String, region: String, endpoint: String?) -> Target {
        let encodedKey = encodePath(objectKey)
        if let endpoint, let raw = nonEmpty(endpoint) {
            // S3-compatible endpoint → path-style addressing (capcap `S3Common.stripScheme`).
            let host = stripScheme(raw)
            return Target(host: host, canonicalURI: "/\(bucket)/\(encodedKey)")
        }
        // Amazon S3 → virtual-hosted-style addressing.
        let host = "\(bucket).s3.\(region).amazonaws.com"
        return Target(host: host, canonicalURI: "/\(encodedKey)")
    }

    /// Mirrors capcap `R2Uploader` host / canonical URI selection.
    static func r2Target(accountID: String, bucket: String, objectKey: String) -> Target {
        let encodedKey = encodePath(objectKey)
        let normalizedAccountID = normalizeAccountID(accountID)
        return Target(
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
        let (payloadHash, contentLength) = try sha256File(file)
        let request = try signedPutRequest(
            host: target.host,
            canonicalURI: target.canonicalURI,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            payloadHash: payloadHash,
            contentLength: contentLength,
            contentType: contentType
        )
        let (body, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        try validate(response: response, body: body)
    }

    static func deleteObject(
        target: Target,
        region: String,
        accessKeyId: String,
        secretAccessKey: String
    ) async throws {
        let request = try signedDeleteRequest(
            host: target.host,
            canonicalURI: target.canonicalURI,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey
        )
        let (body, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, body: body)
    }

    /// Empty-body DELETE SigV4 request (same empty payload hash as AWS docs).
    static func signedDeleteRequest(
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        now: Date = Date()
    ) throws -> URLRequest {
        try signedRequest(
            method: "DELETE",
            host: host,
            canonicalURI: canonicalURI,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            contentType: nil,
            contentSHA256: emptyPayloadHash,
            contentLength: nil,
            now: now
        )
    }

    /// capcap `AWSV4Signer.signedPutRequest` — same headers, same signature inputs.
    static func signedPutRequest(
        host: String,
        canonicalURI: String,
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
            host: host,
            canonicalURI: canonicalURI,
            region: region,
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            contentType: contentType,
            contentSHA256: payloadHash,
            contentLength: contentLength,
            now: now
        )
        // capcap sets Content-Length explicitly on the signed PUT.
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        return request
    }

    /// Deterministic helper for tests — same as hashing `payload` then calling `signedPutRequest`.
    static func signedPutRequest(
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        payload: Data,
        contentType: String,
        now: Date = Date()
    ) throws -> URLRequest {
        try signedPutRequest(
            host: host,
            canonicalURI: canonicalURI,
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

    // MARK: - Path / endpoint helpers (capcap)

    /// capcap `AWSV4Signer.encodePath`
    static func encodePath(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: false)
            .map { String($0).sharePercentEncoded() }
            .joined(separator: "/")
    }

    /// capcap `S3Common.stripScheme`
    static func stripScheme(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") { value.removeFirst(8) }
        if value.hasPrefix("http://") { value.removeFirst(7) }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    /// capcap `R2Uploader.normalizeAccountId`
    static func normalizeAccountID(_ raw: String) -> String {
        var value = stripScheme(raw)
        if let range = value.range(of: ".r2.cloudflarestorage.com") {
            value = String(value[value.startIndex..<range.lowerBound])
        }
        return value
    }

    // MARK: - Private

    static func signedRequest(
        method: String,
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        contentType: String?,
        contentSHA256: String,
        contentLength: Int?,
        now: Date = Date()
    ) throws -> URLRequest {
        guard let url = URL(string: "https://\(host)\(canonicalURI)") else {
            throw ShareError.notConfigured
        }

        let (amzDate, dateStamp) = timestamps(now)
        let service = "s3"

        // Canonical headers must be sorted by lowercased name (capcap PUT order).
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
            canonicalURI,
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

        // Exact Authorization formatting from capcap `AWSV4Signer`.
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

    private static func nonEmpty(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
