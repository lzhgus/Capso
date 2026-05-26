import Foundation

public actor AliyunOSSDestination: ShareDestination {
    private let config: ShareConfig
    private let accessKeyID: String
    private let accessKeySecret: String

    public init(config: ShareConfig, accessKeyID: String, accessKeySecret: String) {
        self.config = config
        self.accessKeyID = accessKeyID
        self.accessKeySecret = accessKeySecret
    }

    public func upload(file: URL, key: String, contentType: String) async throws -> URL {
        let objectKey = config.objectKey(for: key)
        let request = try signedRequest(method: "PUT", objectKey: objectKey, contentType: contentType)
        try await ShareHTTP.upload(request: request, file: file)
        return config.publicURL(forObjectKey: objectKey)
    }

    public func delete(key: String) async throws {
        let objectKey = config.objectKey(for: key)
        let request = try signedRequest(method: "DELETE", objectKey: objectKey, contentType: nil)
        try await ShareHTTP.data(request: request)
    }

    private func signedRequest(method: String, objectKey: String, contentType: String?) throws -> URLRequest {
        let host = "\(config.bucket).\(normalizedEndpoint(config.region))"
        let encodedKey = ShareConfig.encodeObjectKey(objectKey)
        guard let url = URL(string: "https://\(host)/\(encodedKey)") else {
            throw ShareError.notConfigured
        }

        let date = ShareSigning.rfc1123Date()
        let contentTypeForSignature = contentType ?? ""
        let resource = "/\(config.bucket)/\(objectKey)"
        let aclHeader = method == "PUT" ? "x-oss-object-acl:public-read\n" : ""
        let stringToSign = "\(method)\n\n\(contentTypeForSignature)\n\(date)\n\(aclHeader)\(resource)"
        let signature = ShareSigning.base64(
            ShareSigning.hmacSHA1(key: accessKeySecret, message: stringToSign)
        )

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(date, forHTTPHeaderField: "Date")
        request.setValue("OSS \(accessKeyID):\(signature)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("public-read", forHTTPHeaderField: "x-oss-object-acl")
        }
        return request
    }

    private func normalizedEndpoint(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://") {
            value.removeFirst("https://".count)
        }
        if value.hasPrefix("http://") {
            value.removeFirst("http://".count)
        }
        while value.hasSuffix("/") {
            value.removeLast()
        }
        if !value.contains(".") {
            value += ".aliyuncs.com"
        }
        return value
    }
}
