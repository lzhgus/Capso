import CryptoKit
import Foundation
import Testing
@testable import ShareKit

@Suite("S3CompatibleHTTP")
struct S3CompatibleHTTPTests {

    // MARK: - Addressing

    @Test("Amazon S3 uses virtual-hosted HTTPS when endpoint is empty")
    func amazonVirtualHosted() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "clips/demo.mp4",
            region: "us-west-2",
            endpoint: nil
        )
        #expect(target.scheme == "https")
        #expect(target.host == "capso.s3.us-west-2.amazonaws.com")
        #expect(target.canonicalURI == "/clips/demo.mp4")
        #expect(target.requestURLString == "https://capso.s3.us-west-2.amazonaws.com/clips/demo.mp4")
    }

    @Test("Amazon S3 treats blank endpoint as virtual-hosted")
    func amazonBlankEndpoint() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "a.png",
            region: "eu-central-1",
            endpoint: "   "
        )
        #expect(target.scheme == "https")
        #expect(target.host == "capso.s3.eu-central-1.amazonaws.com")
    }

    @Test("custom HTTPS endpoint uses path-style addressing")
    func amazonCustomHTTPSEndpoint() {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "clips/demo one.mp4",
            region: "us-east-1",
            endpoint: "https://minio.example.com/"
        )
        #expect(target.scheme == "https")
        #expect(target.host == "minio.example.com")
        #expect(target.canonicalURI == "/capso/clips/demo%20one.mp4")
        #expect(target.requestURLString == "https://minio.example.com/capso/clips/demo%20one.mp4")
    }

    @Test("custom HTTP endpoint preserves http scheme and port")
    func amazonCustomHTTPEndpointPreservesScheme() throws {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "shots",
            objectKey: "x.png",
            region: "us-east-1",
            endpoint: "http://127.0.0.1:9000"
        )
        #expect(target.scheme == "http")
        #expect(target.host == "127.0.0.1:9000")
        #expect(target.canonicalURI == "/shots/x.png")
        #expect(target.requestURLString == "http://127.0.0.1:9000/shots/x.png")

        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: Data("x".utf8),
            contentType: "image/png",
            now: Self.fixedDate
        )
        #expect(request.url?.scheme == "http")
        #expect(request.url?.absoluteString == "http://127.0.0.1:9000/shots/x.png")
        #expect(request.value(forHTTPHeaderField: "Host") == "127.0.0.1:9000")
    }

    @Test("endpoint path is folded into the canonical URI, not the Host header")
    func endpointPathGoesIntoCanonicalURI() throws {
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: "capso",
            objectKey: "a.png",
            region: "us-east-1",
            endpoint: "https://minio.example.com/base"
        )
        #expect(target.scheme == "https")
        #expect(target.host == "minio.example.com")
        #expect(target.canonicalURI == "/base/capso/a.png")
        #expect(target.requestURLString == "https://minio.example.com/base/capso/a.png")

        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: Data("x".utf8),
            contentType: "image/png",
            now: Self.fixedDate
        )
        #expect(request.value(forHTTPHeaderField: "Host") == "minio.example.com")
        #expect(request.url?.path == "/base/capso/a.png")
    }

    @Test("bare host endpoint defaults to https")
    func bareHostDefaultsToHTTPS() {
        let parsed = S3CompatibleHTTP.parseEndpoint("minio.lan:9000")
        #expect(parsed == .init(scheme: "https", host: "minio.lan:9000", pathPrefix: ""))
    }

    @Test("R2 target uses account endpoint and path-style bucket")
    func r2Target() {
        let target = S3CompatibleHTTP.r2Target(
            accountID: "abc123",
            bucket: "capso",
            objectKey: "a/b.png"
        )
        #expect(target.scheme == "https")
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
        #expect(S3CompatibleHTTP.normalizeAccountID("https://abc123.r2.cloudflarestorage.com/") == "abc123")
        #expect(S3CompatibleHTTP.normalizeAccountID("abc123") == "abc123")
    }

    // MARK: - SigV4 PUT

    @Test("signed PUT uses payload-hash SigV4 shape")
    func signedPutShape() throws {
        let payload = Data("hello-capso".utf8)
        let payloadHash = Self.sha256Hex(payload)
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "capso.s3.us-east-1.amazonaws.com",
            canonicalURI: "/demo.mp4"
        )

        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKIAIOSFODNN7EXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            payload: payload,
            contentType: "video/mp4",
            now: Self.fixedDate
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

    @Test("signed PUT Authorization matches an independent SigV4 implementation")
    func signedPutMatchesIndependentSigner() throws {
        let payload = Data("wire-compatible".utf8)
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "bucket.s3.us-west-2.amazonaws.com",
            canonicalURI: "/clips/demo.mp4"
        )
        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-west-2",
            accessKeyId: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            payload: payload,
            contentType: "video/mp4",
            now: Self.fixedDate
        )

        let expected = Self.independentAuthorization(
            method: "PUT",
            host: target.host,
            canonicalURI: target.canonicalURI,
            region: "us-west-2",
            accessKeyId: "AKIDEXAMPLE",
            secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
            contentType: "video/mp4",
            payloadHash: Self.sha256Hex(payload),
            now: Self.fixedDate
        )
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test("R2 PUT signs with region auto")
    func r2PutUsesAutoRegion() throws {
        let target = S3CompatibleHTTP.r2Target(accountID: "abc123", bucket: "capso", objectKey: "shot.png")
        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "auto",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: Data("r2".utf8),
            contentType: "image/png",
            now: Self.fixedDate
        )
        let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
        #expect(authorization.contains("/20260730/auto/s3/aws4_request"))
    }

    @Test("payload-hash overload and explicit hash overload produce the same signature")
    func payloadAndHashOverloadsMatch() throws {
        let payload = Data("same-bytes".utf8)
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/k"
        )
        let fromPayload = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payload: payload,
            contentType: "text/plain",
            now: Self.fixedDate
        )
        let fromHash = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payloadHash: Self.sha256Hex(payload),
            contentLength: payload.count,
            contentType: "text/plain",
            now: Self.fixedDate
        )
        #expect(fromPayload.value(forHTTPHeaderField: "Authorization") == fromHash.value(forHTTPHeaderField: "Authorization"))
        #expect(fromPayload.value(forHTTPHeaderField: "X-Amz-Content-Sha256") == fromHash.value(forHTTPHeaderField: "X-Amz-Content-Sha256"))
        #expect(fromPayload.value(forHTTPHeaderField: "Content-Length") == fromHash.value(forHTTPHeaderField: "Content-Length"))
    }

    @Test("empty payload uses the AWS empty-body SHA-256")
    func emptyPayloadHash() throws {
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/empty.txt"
        )
        let request = try S3CompatibleHTTP.signedPutRequest(
            target: target,
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

    @Test("invalid request URL maps to unknown, not notConfigured")
    func invalidURLMapsToUnknown() {
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "host with spaces",
            canonicalURI: "/k"
        )
        #expect(throws: ShareError.self) {
            _ = try S3CompatibleHTTP.signedPutRequest(
                target: target,
                region: "us-east-1",
                accessKeyId: "AKID",
                secretAccessKey: "SECRET",
                payload: Data("x".utf8),
                contentType: "text/plain",
                now: Self.fixedDate
            )
        }
        do {
            _ = try S3CompatibleHTTP.signedPutRequest(
                target: target,
                region: "us-east-1",
                accessKeyId: "AKID",
                secretAccessKey: "SECRET",
                payload: Data("x".utf8),
                contentType: "text/plain",
                now: Self.fixedDate
            )
            Issue.record("expected throw")
        } catch let error as ShareError {
            #expect(error == .unknown("Invalid S3 endpoint URL"))
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    // MARK: - SigV4 DELETE

    @Test("signed DELETE uses empty payload hash and omits content-type")
    func signedDeleteShape() throws {
        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "capso.s3.us-east-1.amazonaws.com",
            canonicalURI: "/old.mp4"
        )
        let request = try S3CompatibleHTTP.signedDeleteRequest(
            target: target,
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
        let target = S3CompatibleHTTP.r2Target(accountID: "abc123", bucket: "capso", objectKey: "old.png")
        let request = try S3CompatibleHTTP.signedDeleteRequest(
            target: target,
            region: "auto",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            now: Self.fixedDate
        )
        let expected = Self.independentAuthorization(
            method: "DELETE",
            host: target.host,
            canonicalURI: target.canonicalURI,
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

        let target = S3CompatibleHTTP.Target(
            scheme: "https",
            host: "bucket.s3.us-east-1.amazonaws.com",
            canonicalURI: "/clip.mp4"
        )
        let fileDigest = try S3CompatibleHTTP.sha256File(url)
        let fromFile = try S3CompatibleHTTP.signedPutRequest(
            target: target,
            region: "us-east-1",
            accessKeyId: "AKID",
            secretAccessKey: "SECRET",
            payloadHash: fileDigest.hash,
            contentLength: fileDigest.size,
            contentType: "video/mp4",
            now: Self.fixedDate
        )
        let fromMemory = try S3CompatibleHTTP.signedPutRequest(
            target: target,
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
        let body = Data("<Error><Code>NoSuchBucket</Code><Message>gone</Message></Error>".utf8)
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

    // MARK: - Destinations / public URL

    @Test("S3 and R2 destinations still construct through the factory")
    func destinationsConstruct() throws {
        let s3 = ShareConfig(
            provider: .s3,
            urlPrefix: "https://cdn.example.com",
            bucket: "capso",
            fields: ["region": "us-east-1", "endpoint": "http://minio.example.com"]
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

    @Test("publicURL does not trap on unusual encoded keys")
    func publicURLIsNonTrapping() {
        let config = ShareConfig(
            provider: .s3,
            urlPrefix: "https://cdn.example.com",
            bucket: "capso",
            fields: ["region": "us-east-1"]
        )
        let url = config.publicURL(forObjectKey: "a/b c.png")
        #expect(url.absoluteString == "https://cdn.example.com/a/b%20c.png")
    }

    // MARK: - Helpers

    private static let fixedDate = ISO8601DateFormatter().date(from: "2026-07-30T12:00:00Z")!

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Second implementation of the same SigV4 Authorization string — catches accidental
    /// drift in the production signer, not a shared helper call.
    private static func independentAuthorization(
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
