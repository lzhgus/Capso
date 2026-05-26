import Foundation
import Testing
@testable import ShareKit

@Suite("Share providers")
struct ShareProviderTests {
    @Test("supported providers include R2, S3, Tencent COS, and Aliyun OSS")
    func supportedProviders() {
        #expect(ShareProvider.allCases == [.r2, .s3, .tencentCOS, .aliyunOSS])
        #expect(ShareProvider.s3.displayName == "Amazon S3")
        #expect(ShareProvider.tencentCOS.displayName == "Tencent COS")
        #expect(ShareProvider.aliyunOSS.displayName == "Aliyun OSS")
    }

    @Test("R2 compatibility initializer stores account ID in provider fields")
    func r2CompatibilityInitializer() {
        let config = ShareConfig(
            provider: .r2,
            urlPrefix: "https://pub.example.com/",
            accountID: "abc123",
            bucket: "capso"
        )

        #expect(config.urlPrefix == "https://pub.example.com")
        #expect(config.bucket == "capso")
        #expect(config.accountID == "abc123")
        #expect(config.value("accountID") == "abc123")
    }

    @Test("object keys support optional path prefixes")
    func objectKeysSupportPathPrefixes() {
        let config = ShareConfig(
            provider: .s3,
            urlPrefix: "https://cdn.example.com",
            bucket: "capso",
            fields: ["region": "us-east-1", "pathPrefix": "/screenshots/"]
        )

        #expect(config.objectKey(for: "capture one.png") == "screenshots/capture one.png")
        #expect(config.publicURL(forObjectKey: config.objectKey(for: "capture one.png")).absoluteString == "https://cdn.example.com/screenshots/capture%20one.png")
    }

    @Test("destination factory creates provider-specific destinations")
    func destinationFactory() throws {
        let r2 = ShareConfig(provider: .r2, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["accountID": "abc123"])
        let s3 = ShareConfig(provider: .s3, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["region": "us-east-1"])
        let cos = ShareConfig(provider: .tencentCOS, urlPrefix: "https://cdn.example.com", bucket: "capso-123456", fields: ["region": "ap-guangzhou"])
        let oss = ShareConfig(provider: .aliyunOSS, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["region": "oss-cn-hangzhou"])

        #expect(try ShareDestinationFactory.make(config: r2, accessKey: "id", secretKey: "secret") is R2Destination)
        #expect(try ShareDestinationFactory.make(config: s3, accessKey: "id", secretKey: "secret") is S3Destination)
        #expect(try ShareDestinationFactory.make(config: cos, accessKey: "id", secretKey: "secret") is TencentCOSDestination)
        #expect(try ShareDestinationFactory.make(config: oss, accessKey: "id", secretKey: "secret") is AliyunOSSDestination)
    }
}
