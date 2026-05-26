import CryptoKit
import Foundation

enum ShareSigning {
    static func hmacSHA1(key: String, message: String) -> Data {
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: Data(key.utf8))
        )
        return Data(signature)
    }

    static func sha1Hex(_ text: String) -> String {
        hex(Data(Insecure.SHA1.hash(data: Data(text.utf8))))
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func base64(_ data: Data) -> String {
        data.base64EncodedString()
    }

    static func rfc1123Date(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }
}

enum ShareHTTP {
    static func upload(request: URLRequest, file: URL) async throws {
        let (_, response) = try await URLSession.shared.upload(for: request, fromFile: file)
        try validate(response: response)
    }

    static func data(request: URLRequest) async throws {
        let (_, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ShareError.network(underlying: "Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403:
                throw ShareError.invalidCredentials
            case 413, 507:
                throw ShareError.quotaExceeded
            default:
                throw ShareError.unknown("HTTP \(http.statusCode)")
            }
        }
    }
}
