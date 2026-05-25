import Foundation
import SharedKit

public struct TranslationProviderConfiguration: Sendable {
    public let apiKey: String
    public let endpoint: String
    public let model: String

    public init(apiKey: String, endpoint: String, model: String) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.model = model
    }
}

public struct ProviderTranslationResult: Sendable {
    public let text: String
    public let detectedSource: String?

    public init(text: String, detectedSource: String?) {
        self.text = text
        self.detectedSource = detectedSource
    }
}

public enum ProviderTranslationError: LocalizedError, Sendable {
    case missingAPIKey
    case badEndpoint
    case badResponse
    case httpStatus(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Translation provider API key is missing."
        case .badEndpoint:
            return "Translation provider endpoint is invalid."
        case .badResponse:
            return "Translation provider returned an unreadable response."
        case .httpStatus(let code, let body):
            return body.isEmpty ? "Translation provider returned HTTP \(code)." : "Translation provider returned HTTP \(code): \(body)"
        }
    }
}

public enum ProviderTranslationService {
    public static func translate(
        text: String,
        target: String,
        provider: TranslationProviderKind,
        config: TranslationProviderConfiguration
    ) async throws -> ProviderTranslationResult {
        let request = try makeRequest(text: text, target: target, provider: provider, config: config)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderTranslationError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderTranslationError.httpStatus(http.statusCode, String(body.prefix(600)))
        }

        if provider == .deepL {
            return try parseDeepLResponse(data)
        }
        return try parseChatCompletionResponse(data)
    }

    public static func makeRequest(
        text: String,
        target: String,
        provider: TranslationProviderKind,
        config: TranslationProviderConfiguration
    ) throws -> URLRequest {
        switch provider {
        case .apple:
            throw ProviderTranslationError.badEndpoint
        case .deepL:
            return try makeDeepLRequest(text: text, target: target, config: config)
        case .openAICompatible, .custom:
            return try makeChatCompletionRequest(
                text: text,
                target: target,
                provider: provider,
                config: config
            )
        }
    }

    private static func makeChatCompletionRequest(
        text: String,
        target: String,
        provider: TranslationProviderKind,
        config: TranslationProviderConfiguration
    ) throws -> URLRequest {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if provider != .custom && apiKey.isEmpty {
            throw ProviderTranslationError.missingAPIKey
        }

        let endpoint = resolvedEndpoint(provider: provider, config: config)
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw ProviderTranslationError.badEndpoint
        }

        let model = resolvedModel(provider: provider, config: config)
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt(target: target)],
                ["role": "user", "content": text],
            ],
        ])
        return request
    }

    private static func makeDeepLRequest(
        text: String,
        target: String,
        config: TranslationProviderConfiguration
    ) throws -> URLRequest {
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else { throw ProviderTranslationError.missingAPIKey }
        guard let url = URL(string: resolvedDeepLEndpoint(config: config, apiKey: apiKey)) else {
            throw ProviderTranslationError.badEndpoint
        }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": [text],
            "target_lang": deepLTargetCode(target),
            "preserve_formatting": true,
        ])
        return request
    }

    private static func parseChatCompletionResponse(_ data: Data) throws -> ProviderTranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ProviderTranslationError.badResponse
        }
        return ProviderTranslationResult(
            text: content.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedSource: nil
        )
    }

    private static func parseDeepLResponse(_ data: Data) throws -> ProviderTranslationResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = json["translations"] as? [[String: Any]],
              let first = translations.first,
              let text = first["text"] as? String else {
            throw ProviderTranslationError.badResponse
        }
        return ProviderTranslationResult(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedSource: first["detected_source_language"] as? String
        )
    }

    private static func resolvedEndpoint(
        provider: TranslationProviderKind,
        config: TranslationProviderConfiguration
    ) -> String {
        let endpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return endpoint.isEmpty ? provider.defaultEndpoint : endpoint
    }

    private static func resolvedModel(
        provider: TranslationProviderKind,
        config: TranslationProviderConfiguration
    ) -> String {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? provider.defaultModel : model
    }

    private static func systemPrompt(target: String) -> String {
        let targetName = Locale.current.localizedString(forIdentifier: target) ?? target
        return """
        Translate the user's text into \(targetName). If the text is already in \(targetName), translate it into English instead. Return only the final translation. Preserve line breaks.
        """
    }

    private static func resolvedDeepLEndpoint(config: TranslationProviderConfiguration, apiKey: String) -> String {
        let endpoint = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpoint.isEmpty { return endpoint }
        return apiKey.lowercased().hasSuffix(":fx")
            ? "https://api-free.deepl.com/v2/translate"
            : "https://api.deepl.com/v2/translate"
    }

    private static func deepLTargetCode(_ target: String) -> String {
        switch target {
        case "zh-Hans": return "ZH-HANS"
        case "zh-Hant": return "ZH-HANT"
        case "pt-BR": return "PT-BR"
        default:
            return target.uppercased()
        }
    }
}
