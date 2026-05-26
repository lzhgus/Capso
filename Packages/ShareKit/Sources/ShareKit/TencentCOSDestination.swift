import Foundation

public actor TencentCOSDestination: ShareDestination {
    private let config: ShareConfig
    private let secretID: String
    private let secretKey: String

    public init(config: ShareConfig, secretID: String, secretKey: String) {
        self.config = config
        self.secretID = secretID
        self.secretKey = secretKey
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
        let host = "\(config.bucket).cos.\(config.region).myqcloud.com"
        let encodedKey = ShareConfig.encodeObjectKey(objectKey)
        guard let url = URL(string: "https://\(host)/\(encodedKey)") else {
            throw ShareError.notConfigured
        }

        let now = Int(Date().timeIntervalSince1970)
        let keyTime = "\(now);\(now + 3600)"
        let signKey = ShareSigning.hex(ShareSigning.hmacSHA1(key: secretKey, message: keyTime))
        let httpString = "\(method.lowercased())\n/\(encodedKey)\n\n\n"
        let stringToSign = "sha1\n\(keyTime)\n\(ShareSigning.sha1Hex(httpString))\n"
        let signature = ShareSigning.hex(ShareSigning.hmacSHA1(key: signKey, message: stringToSign))
        let authorization = "q-sign-algorithm=sha1"
            + "&q-ak=\(secretID)"
            + "&q-sign-time=\(keyTime)"
            + "&q-key-time=\(keyTime)"
            + "&q-header-list="
            + "&q-url-param-list="
            + "&q-signature=\(signature)"

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
