import CryptoKit
import Foundation
import Testing
@testable import ShareKit

@Suite("S3CompatibleHTTP")
struct S3CompatibleHTTPTests {

    // MARK: - Addressing (capcap S3Uploader / R2Uploader)

    @Test("Amazon S3 uses virtual-hosted style when endpoint is empty")
    func amazonVirtualHosted() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "clips/demo.mp4",
            region: "us-west-2",
            endpoint: nil
        )
        #expect(target.host == "capso.s3.us-west-2.amazonaws.com")
        #expect(target.canonicalURI == "/clips/demo.mp4")
    }

    @Test("Amazon S3 treats blank endpoint as virtual-hosted")
    func amazonBlankEndpoint() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "a.png",
            region: "eu-central-1",
            endpoint: "   "
        )
        #expect(target.host == "capso.s3.eu-central-1.amazonaws.com")
        #expect(target.canonicalURI == "/a.png")
    }

    @Test("Amazon S3 uses path-style addressing for custom endpoints")
    func amazonCustomEndpoint() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "clips/demo one.mp4",
            region: "us-east-1",
            endpoint: "https://minio.example.com/"
        )
        #expect(target.host == "minio.example.com")
        #expect(target.canonicalURI == "/capso/clips/demo%20one.mp4")
    }

    @Test("custom endpoint stripScheme keeps host:port like capcap")
    func customEndpointWithPort() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "shots",
            objectKey: "x.png",
            region: "us-east-1",
            endpoint: "http://127.0.0.1:9000"
        )
        #expect(target.host == "127.0.0.1:9000")
        #expect(target.canonicalURI == "/shots/x.png")
    }

    @Test("R2 target uses account endpoint and path-style bucket")
    func r2Target() {
        let target = S3CompatibleHTTP.r2Target(
            accountID: "abc123",
            bucket: "capso",
            objectKey: "a/b.png"
        )
        #expect(target.host == "abc123.r2.cloudflarestorage.com")
        #expect(target.canonicalURI == "/capso/a/b.png")
    }

    @Test("R2 account ID accepts a pasted full endpoint")
    func r2NormalizesAccountID() {
        let target = S3CompatibleHTTP.r2Target(
            accountID: "https://abc123.r2.cloudflarestorage.com",
            bucket: "capso",
            objectKey: "x.png"
        )
        #expect(target.host == "abc123.r2.cloudflarestorage.com")
    }

    @Test("R2 account ID normalization strips scheme and trailing slash")
    func r2NormalizeHelpers() {
        #expect(S3CompatibleHTTP.normalizeAccountID("abc123") == "abc123")
        #expect(S3CompatibleHTTP.normalizeAccountID("https://abc123.r2.cloudflarestorage.com/") == "abc123")
        #expect(S3CompatibleHTTP.stripScheme("https://minio.example.com/") == "minio.example.com")
        #expect(S3CompatibleHTTP.stripScheme("http://minio.example.com") == "minio.example.com")
    }

    // MARK: - Path encoding (capcap AWSV4Signer.encodePath)

    @Test("encodePath percent-encodes segments and preserves slashes")
    func encodePathRules() {
        #expect(S3CompatibleHTTP.encodePath("a/b c.png") == "a/b%20c.png")
        #expect(S3CompatibleHTTP.encodePath("已截图.png") == "%E5%B7%B2%E6%88%AA%E5%9B%BE.png")
        #expect(S3CompatibleHTTP.encodePath("a+b~c_d-e.f") == "a%2Bb~c_d-e.f")
        // Empty segments from leading / doubled slashes are preserved.
        #expect(S3CompatibleHTTP.encodePath("/leading") == "/leading")
        #expect(S3CompatibleHTTP.encodePath("a//b") == "a//b")
    }

    @Test("encodePath matches ShareConfig.encodeObjectKey")
    func encodePathMatchesShareConfig() {
        let keys = ["plain.png", "has space.mp4", "path/nested/file.gif", "emoji-🎬.mov"]
        for key in keys {
            #expect(S3CompatibleHTTP.encodePath(key) == ShareConfig.encodeObjectKey(key))
        }
    }

    // MARK: - SigV4 PUT (capcap AWSV4Signer.signedPutRequest)

    @Test("signed PUT matches capcap payload-hash SigV4 shape")
    func signedPutMatchesCapcapShape() throws {
        let payload = Data("hello-capso".utf8)
        let payloadHash = Self.sha256Hex(payload)
        let date = Self.fixedDate

        let request = try S3CompatibleHTTP.signedPutRequest(
            host: "capso.s3.us-east-1.amazonaws.com",
            canonicalURI: "/demo.mp4",
            region: "us-east-1",
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            payload: payload,
            contentType: "video/mp4",
            now: date
        )

        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == payloadHash)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "video/mp4")
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "\(payload.count)")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Date") == "20260730T120000Z")
        #expect(request.value(forHTTPHeaderField: "Host") == "capso.s3.us-east-1.amazonaws.com")
        #expect(request.url?.absoluteString == "https://capso.s3.us-east-1.amazonaws.com/demo.mp4")

        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.hasPrefix("AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20260730/us-east-1/s3/aws4_request, "))
        #expect(authorization.contains("SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date, "))
        #expect(authorization.contains("Signature="))
    }

    @Test("signed PUT Authorization matches an independent capcap-style signer")
    func signedPutMatchesIndependentCapcapSigner() throws {
        let payload = Data("wire-compatible".utf8)
        let date = Self.fixedDate
        let host = "bucket.s3.us-west-2.amazonaws.com"
        let uri = "/clips/demo.mp4"
        let region = "us-west-2"
        let accessKey = "AKIDEXAMPLE"
        let secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let contentType = "video/mp4"

        let request = try S3CompatibleHTTP.signedPutRequest(
            host: host,
            canonicalURI: uri,
            region: region,
            accessKeyId: accessKey,
            secretAccessKey: secret,
            payload: payload,
            contentType: contentType,
            now: date
        )

        let expected = Self.capcapStyleAuthorization(
            method: "PUT",
            host: host,
            canonicalURI: uri,
            region: region,
            accessKeyId: accessKey,
            secretAccessKey: secret,
            contentType: contentType,
            payloadHash: Self.sha256Hex(payload),
            now: date
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test("R2 PUT signs with region auto like capcap R2Uploader")
    func r2PutUsesAutoRegion() throws {
        let payload = Data("r2".utf8)
        let request = try S3CompatibleHTTP.signedPutRequest(
            host: "abc123.r2.cloudflarestorage.com",
            canonicalURI: "/capso/shot.png",
            region: "auto",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: payload,
            contentType: "image/png",
            now: Self.fixedDate
        )
        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.contains("/20260730/auto/s3/aws4_request"))
    }

    @Test("payload-hash overload and explicit hash overload produce the same signature")
    func payloadAndHashOverloadsMatch() throws {
        let payload = Data("same-bytes".utf8)
        let date = Self.fixedDate
        let fromPayload = try S3CompatibleHTTP.signedPutRequest(
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/k",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: payload,
            contentType: "text/plain",
            now: date
        )
        let fromHash = try S3CompatibleHTTP.signedPutRequest(
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/k",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payloadHash: Self.sha256Hex(payload),
            contentLength: payload.count,
            contentType: "text/plain",
            now: date
        )
        #expect(fromPayload.value(forHTTPHeaderField: "Authorization") == fromHash.value(forHTTPHeaderField: "Authorization"))
        #expect(fromPayload.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == fromHash.value(forHTTPHeaderField: "X-Amz-Content-Sha256"))
        #expect(fromPayload.value(forHTTPHeaderField: "Content-Length") == fromHash.value(forHTTPHeaderField: "Content-Length"))
    }

    @Test("empty payload uses the AWS empty-body SHA-256")
    func emptyPayloadHash() throws {
        let request = try S3CompatibleHTTP.signedPutRequest(
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/empty.txt",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: Data(),
            contentType: "text/plain",
            now: Self.fixedDate
        )
        #expect(request.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == S3CompatibleHTTP.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "Content-Length") == "0")
    }

    // MARK: - SigV4 DELETE

    @Test("signed DELETE uses empty payload hash and omits content-type")
    func signedDeleteShape() throws {
        let request = try S3CompatibleHTTP.signedDeleteRequest(
            host: "capso.s3.us-east-1.amazonaws.com",
            canonicalURI: "/old.mp4",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            now: Self.fixedDate
        )
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == S3CompatibleHTTP.emptyPayloadHash)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Length") == nil)

        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.contains("SignedHeaders=host;x-amz-content-sha256;x-amz-date, "))
        #expect(authorization.contains("/us-east-1/s3/aws4_request"))
    }

    @Test("signed DELETE Authorization matches independent signer")
    func signedDeleteMatchesIndependentSigner() throws {
        let host = "abc123.r2.cloudflarestorage.com"
        let uri = "/capso/old.png"
        let request = try S3CompatibleHTTP.signedDeleteRequest(
            host: host,
            canonicalURI: uri,
            region: "auto",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            now: Self.fixedDate
        )
        let expected = Self.capcapStyleAuthorization(
            method: "DELETE",
            host: host,
            canonicalURI: uri,
            region: "auto",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            contentType: nil,
            payloadHash: S3CompatibleHTTP.emptyPayloadHash,
            now: Self.fixedDate
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    }

    // MARK: - Chunked file hashing

    @Test("chunked sha256File matches Data(contentsOf:) for small files")
    func sha256FileMatchesDataSmall() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-sha-small-\(UUID().uuidString).bin")
        let data = Data("small-recording-bytes".utf8)
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hashed = try S3CompatibleHTTP.sha256File(url)
        #expect(hashed.size == data.count)
        #expect(hashed.hash == Self.sha256Hex(data))
    }

    @Test("chunked sha256File matches Data(contentsOf:) across 1MB boundaries")
    func sha256FileMatchesDataLarge() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-sha-large-\(UUID().uuidString).bin")
        // 1.5 MiB forces more than one 1 MiB read chunk in sha256File.
        var data = Data(count: 1_500_000)
        for i in data.indices {
            data[i] = UInt8(i % 251)
        }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let hashed = try S3CompatibleHTTP.sha256File(url)
        #expect(hashed.size == data.count)
        #expect(hashed.hash == Self.sha256Hex(data))
    }

    @Test("chunked file hash produces the same PUT signature as in-memory payload")
    func fileHashSignatureMatchesPayloadSignature() throws {
        let payload = Data(repeating: 0x5A, count: 4096)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("capso-sig-\(UUID().uuidString).bin")
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let fileDigest = try S3CompatibleHTTP.sha256File(url)
        let fromFile = try S3CompatibleHTTP.signedPutRequest(
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/clip.mp4",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payloadHash: fileDigest.hash,
            contentLength: fileDigest.size,
            contentType: "video/mp4",
            now: Self.fixedDate
        )
        let fromMemory = try S3CompatibleHTTP.signedPutRequest(
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/clip.mp4",
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: payload,
            contentType: "video/mp4",
            now: Self.fixedDate
        )
        #expect(fromFile.value(forHTTPHeaderField: "Authorization") == fromMemory.value(forHTTPHeaderField: "Authorization"))
        #expect(fromFile.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == fromMemory.value(forHTTPHeaderField: "X-Amz-Content-Sha256"))
        #expect(fromFile.value(forHTTPHeaderField: "Content-Length") == fromMemory.value(forHTTPHeaderField: "Content-Length"))
    }

    // MARK: - Error mapping

    @Test("maps S3 XML auth failures to invalidCredentials", arguments: [
        "SignatureDoesNotMatch",
        "InvalidAccessKeyId",
        "AccessDenied",
        "InvalidToken",
    ])
    func mapsAuthFailures(code: String) {
        let body = Data("<Error><Code>\(code)</Code><Message>nope</Message></Error>".utf8)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 403, body: body) == .invalidCredentials)
    }

    @Test("maps quota XML codes to quotaExceeded", arguments: ["QuotaExceeded", "EntityTooLarge"])
    func mapsQuotaFailures(code: String) {
        let body = Data("<Error><Code>\(code)</Code><Message>too big</Message></Error>".utf8)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 400, body: body) == .quotaExceeded)
    }

    @Test("maps missing bucket XML to a helpful unknown error")
    func mapsMissingBucket() {
        let body = Data("""
        <Error><Code>NoSuchBucket</Code><Message>gone</Message></Error>
        """.utf8)
        #expect(
            S3CompatibleHTTP.mapResponseError(statusCode: 404, body: body)
                == .unknown("Bucket not found — verify the bucket name in Cloud Share settings")
        )
    }

    @Test("maps unknown XML code with message")
    func mapsUnknownXMLCode() {
        let body = Data("<Error><Code>SlowDown</Code><Message>wait</Message></Error>".utf8)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 503, body: body) == .unknown("SlowDown: wait"))
    }

    @Test("maps HTTP status fallbacks without XML")
    func mapsHTTPStatusFallbacks() {
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 401, body: Data()) == .invalidCredentials)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 403, body: Data()) == .invalidCredentials)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 413, body: Data()) == .quotaExceeded)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 507, body: Data()) == .quotaExceeded)
        #expect(S3CompatibleHTTP.mapResponseError(statusCode: 500, body: Data()) == .unknown("HTTP 500"))
        #expect(
            S3CompatibleHTTP.mapResponseError(statusCode: 500, body: Data("boom".utf8))
                == .unknown("HTTP 500: boom")
        )
    }

    // MARK: - Destinations still construct

    @Test("S3 and R2 destinations still construct through the factory")
    func destinationsConstruct() throws {
        let s3 = ShareConfig(
            provider: .s3,
            urlPrefix: "https://cdn.example.com",
            bucket: "capso",
            fields: ["region": "us-east-1", "endpoint": "https://minio.example.com"]
        )
        let r2 = ShareConfig(
            provider: .r2,
            urlPrefix: "https://cdn.example.com",
            bucket: "capso",
            fields: ["accountID": "abc123"]
        )
        #expect(try ShareDestinationFactory.make(config: s3, accessKey: "id", secretKey: "secret") is S3Destination)
        #expect(try ShareDestinationFactory.make(config: r2, accessKey: "id", secretKey: "secret") is R2Destination)
    }

    // MARK: - Helpers

    private static let fixedDate = ISO8601DateFormatter().date(from: "2026-07-30T12:00:00Z")!

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Independent reimplementation of capcap `AWSV4Signer` Authorization formatting.
    private static func capcapStyleAuthorization(
        method: String,
        host: String,
        canonicalURI: String,
        region: String,
        accessKeyId: String,
        secretAccessKey: String,
        contentType: String?,
        payloadHash: String,
        now: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let amzDate = formatter.string(from: now)
        formatter.dateFormat = "yyyyMMdd"
        let dateStamp = formatter.string(from: now)

        let canonicalHeaders: String
        let signedHeaders: String
        if let contentType {
            canonicalHeaders =
                "content-type:\(contentType)\n" +
                "host:\(host)\n" +
                "x-amz-content-sha256:\(payloadHash)\n" +
                "x-amz-date:\(amzDate)\n"
            signedHeaders = "content-type;host;x-amz-content-sha256;x-amz-date"
        } else {
            canonicalHeaders =
                "host:\(host)\n" +
                "x-amz-content-sha256:\(payloadHash)\n" +
                "x-amz-date:\(amzDate)\n"
            signedHeaders = "host;x-amz-content-sha256;x-amz-date"
        }

        let canonicalRequest = [
            method,
            canonicalURI,
            "",
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            sha256Hex(Data(canonicalRequest.utf8)),
        ].joined(separator: "\n")

        func hmac(_ key: Data, _ message: Data) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key)))
        }
        let kDate = hmac(Data("AWS4\(secretAccessKey)".utf8), Data(dateStamp.utf8))
        let kRegion = hmac(kDate, Data(region.utf8))
        let kService = hmac(kRegion, Data("s3".utf8))
        let kSigning = hmac(kService, Data("aws4_request".utf8))
        let signature = hmac(kSigning, Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return "AWS4-HMAC-SHA256 " +
            "Credential=\(accessKeyId)/\(scope), " +
            "SignedHeaders=\(signedHeaders), " +
            "Signature=\(signature)"
    }
}
