import Foundation
import Testing
import SharedKit
@testable import TranslationKit

@Suite("Translation provider requests")
struct TranslationProviderRequestTests {
    @Test("OpenAI-compatible providers build chat completion requests")
    func openAICompatibleRequest() throws {
        let config = TranslationProviderConfiguration(
            apiKey: "sk-test",
            endpoint: "https://example.com/v1/chat/completions",
            model: "test-model"
        )

        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .openAICompatible,
            config: config
        )

        #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "test-model")
        #expect(json["stream"] as? Bool == false)
        #expect((json["messages"] as? [[String: String]])?.count == 2)
    }

    @Test("DeepL providers build translate requests")
    func deepLRequest() throws {
        let config = TranslationProviderConfiguration(
            apiKey: "deepl-key:fx",
            endpoint: "",
            model: ""
        )

        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .deepL,
            config: config
        )

        #expect(request.url?.absoluteString == "https://api-free.deepl.com/v2/translate")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "DeepL-Auth-Key deepl-key:fx")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect((json["text"] as? [String]) == ["Hello"])
        #expect(json["target_lang"] as? String == "ZH-HANS")
    }

    @Test("Custom providers can omit API keys for local endpoints")
    func customProviderAllowsMissingAPIKey() throws {
        let config = TranslationProviderConfiguration(
            apiKey: "",
            endpoint: "http://localhost:8317/v1/chat/completions",
            model: "gpt-5.4-mini"
        )

        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .custom,
            config: config
        )

        #expect(request.url?.absoluteString == "http://localhost:8317/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}
