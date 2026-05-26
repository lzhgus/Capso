import Foundation
import SotoS3

public actor S3Destination: ShareDestination {
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
            region: .init(rawValue: config.region),
            endpoint: config.endpoint
        )
    }

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
        let objectKey = config.objectKey(for: key)
        let data = try Data(contentsOf: file)

        return try await withClient { s3 in
            do {
                _ = try await s3.putObject(.init(
                    body: .init(bytes: data),
                    bucket: self.config.bucket,
                    contentType: contentType,
                    key: objectKey
                ))
            } catch let error as S3ErrorType {
                throw self.map(error)
            } catch let error as AWSResponseError {
                throw self.mapResponse(error)
            } catch {
                throw ShareError.network(underlying: error.localizedDescription)
            }

            return self.config.publicURL(forObjectKey: objectKey)
        }
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        try await withClient { s3 in
            do {
                _ = try await s3.deleteObject(.init(bucket: self.config.bucket, key: objectKey))
            } catch let error as S3ErrorType {
                throw self.map(error)
            } catch let error as AWSResponseError {
                throw self.mapResponse(error)
            } catch {
                throw ShareError.network(underlying: error.localizedDescription)
            }
        }
    }

    nonisolated private func map(_ error: S3ErrorType) -> ShareError {
        .unknown("\(error.errorCode): \(error.message ?? "")")
    }

    nonisolated private func mapResponse(_ error: AWSResponseError) -> ShareError {
        switch error.errorCode {
        case "InvalidAccessKeyId", "SignatureDoesNotMatch", "AccessDenied":
            return .invalidCredentials
        case "QuotaExceeded", "EntityTooLarge":
            return .quotaExceeded
        case "NoSuchBucket":
            return .unknown("Bucket not found — verify the bucket name in Cloud Share settings")
        default:
            return .unknown("\(error.errorCode): \(error.message ?? "")")
        }
    }
}
