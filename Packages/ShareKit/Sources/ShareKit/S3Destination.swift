import Foundation

public actor S3Destination: ShareDestination {
    private let config: ShareConfig
    private let accessKey: String
    private let secretKey: String

    public init(config: ShareConfig, accessKey: String, secretKey: String) {
        self.config = config
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: config.bucket,
            objectKey: objectKey,
            region: config.region,
            endpoint: config.endpoint
        )
        try await S3CompatibleHTTP.putObject(
            file: file,
            target: target,
            region: config.region,
            accessKeyId: accessKey,
            secretAccessKey: secretKey,
            contentType: contentType
        )
        return config.publicURL(forObjectKey: objectKey)
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        let target = S3CompatibleHTTP.amazonS3Target(
            bucket: config.bucket,
            objectKey: objectKey,
            region: config.region,
            endpoint: config.endpoint
        )
        try await S3CompatibleHTTP.deleteObject(
            target: target,
            region: config.region,
            accessKeyId: accessKey,
            secretAccessKey: secretKey
        )
    }
}
