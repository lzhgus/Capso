// Packages/ShareKit/Sources/ShareKit/R2Destination.swift

import Foundation
import SotoS3

public actor R2Destination: ShareDestination {
    private let config: ShareConfig
    private let accessKey: String
    private let secretKey: String

    public init(config: ShareConfig, accessKey: String, secretKey: String) {
        self.config = config
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    private func makeClient() -> AWSClient {
        AWSClient(
            credentialProvider: .static(accessKeyId: accessKey, secretAccessKey: secretKey)
        )
    }

    private func makeS3(_ client: AWSClient) -> S3 {
        S3(
            client: client,
            region: .useast1,  // R2 ignores region; placeholder required
            endpoint: "https://\(config.accountID).r2.cloudflarestorage.com"
        )
    }

    /// Run `body` with a fresh AWSClient + S3, awaiting client.shutdown()
    /// before returning. Awaited shutdown avoids the AWSClient.deinit assertion
    /// that fires when a deferred Task runs after the client goes out of scope.
    private func withClient<T: Sendable>(_ body: @Sendable (S3) async throws -> T) async throws -> T {
        let client = makeClient()
        let s3 = makeS3(client)
        do {
            let result = try await body(s3)
            try? await client.shutdown()
            return result
        } catch {
            try? await client.shutdown()
            throw error
        }
    }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        // TODO(v2): stream large files via AWSPayload.stream — current path loads the
        // entire file into memory, which is fine for screenshots (~500KB) but pins
        // RAM proportional to file size for screen recordings (10MB–1GB+).
        let data = try Data(contentsOf: file)

        return try await withClient { s3 in
            do {
                _ = try await s3.putObject(.init(
                    body: .init(bytes: data),
                    bucket: self.config.bucket,
                    contentType: contentType,
                    key: key
                ))
            } catch let error as S3ErrorType {
                throw self.map(error)
            } catch let error as AWSResponseError {
                throw self.mapResponse(error)
            } catch {
                throw ShareError.network(underlying: error.localizedDescription)
            }

            // The public URL is constructed from the user-configured prefix, not from S3 response.
            let parts = key.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let id = String(parts[0])
            let ext = parts.count > 1 ? String(parts[1]) : ""
            return ShareConfig.composePublicURL(prefix: self.config.urlPrefix, id: id, ext: ext)
        }
    }

    public func delete(key: String) async throws {
        try await withClient { s3 in
            do {
                _ = try await s3.deleteObject(.init(bucket: self.config.bucket, key: key))
            } catch let error as S3ErrorType {
                throw self.map(error)
            } catch let error as AWSResponseError {
                throw self.mapResponse(error)
            } catch {
                throw ShareError.network(underlying: error.localizedDescription)
            }
        }
    }

    public func validateConfig() async throws {
        let testID = IDGenerator.shortID()
        let testKey = "_capso_test_\(testID).txt"
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(testKey)
        try "ok".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let publicURL = try await upload(file: tmpFile, key: testKey, contentType: "text/plain")

        // Round-trip: fetch via public URL to confirm public access is enabled
        var request = URLRequest(url: publicURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            try? await delete(key: testKey)
            throw ShareError.publicAccessUnreachable
        }
        guard String(data: data, encoding: .utf8) == "ok" else {
            try? await delete(key: testKey)
            throw ShareError.publicAccessUnreachable
        }

        try await delete(key: testKey)
    }

    // MARK: - Error mapping

    nonisolated private func map(_ error: S3ErrorType) -> ShareError {
        // S3ErrorType only covers S3-specific typed errors (bucket/key not found, etc.)
        .unknown("\(error.errorCode): \(error.message ?? "")")
    }

    nonisolated private func mapResponse(_ error: AWSResponseError) -> ShareError {
        // Auth and quota errors arrive as untyped AWSResponseError from R2/S3.
        let code = error.errorCode
        switch code {
        case "InvalidAccessKeyId", "SignatureDoesNotMatch", "AccessDenied":
            return .invalidCredentials
        case "QuotaExceeded", "EntityTooLarge":
            return .quotaExceeded
        case "NoSuchBucket":
            return .unknown("Bucket not found — verify the bucket name in Cloud Share settings")
        default:
            return .unknown("\(code): \(error.message ?? "")")
        }
    }
}
