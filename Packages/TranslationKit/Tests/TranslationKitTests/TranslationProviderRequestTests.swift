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

    @Test("Keyed providers reject cleartext endpoints")
    func keyedProviderRequiresHTTPS() {
        #expect(throws: ProviderTranslationError.badEndpoint) {
            try ProviderTranslationService.makeRequest(
                text: "Hello",
                target: "zh-Hans",
                provider: .openAICompatible,
                config: TranslationProviderConfiguration(
                    apiKey: "secret",
                    endpoint: "http://example.com/v1/chat/completions",
                    model: "test-model"
                )
            )
        }
    }

    @Test("Custom cleartext endpoints are limited to loopback")
    func customHTTPRequiresLoopback() {
        #expect(throws: ProviderTranslationError.badEndpoint) {
            try ProviderTranslationService.makeRequest(
                text: "Hello",
                target: "zh-Hans",
                provider: .custom,
                config: TranslationProviderConfiguration(
                    apiKey: "",
                    endpoint: "http://192.168.1.20:8317/v1/chat/completions",
                    model: "local-model"
                )
            )
        }
    }

    @Test("DeepSeek uses its official compatible endpoint and disables thinking")
    func deepSeekRequest() throws {
        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .deepSeek,
            config: TranslationProviderConfiguration(apiKey: "deepseek-key", endpoint: "", model: "")
        )

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "deepseek-v4-flash")
        #expect((json["thinking"] as? [String: String])?["type"] == "disabled")
    }

    @Test("OpenRouter uses the official compatible endpoint")
    func openRouterRequest() throws {
        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .openRouter,
            config: TranslationProviderConfiguration(apiKey: "openrouter-key", endpoint: "", model: "")
        )

        #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "openrouter/auto")
    }

    @Test("Google Cloud uses its official API-key header and batch text body")
    func googleCloudRequest() throws {
        let request = try ProviderTranslationService.makeRequest(
            text: "First paragraph\n\nSecond paragraph",
            target: "zh-Hans",
            provider: .googleCloud,
            config: TranslationProviderConfiguration(apiKey: "google-key", endpoint: "", model: "")
        )

        #expect(request.url?.absoluteString == "https://translation.googleapis.com/language/translate/v2")
        #expect(request.value(forHTTPHeaderField: "X-Goog-Api-Key") == "google-key")
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["q"] as? [String] == ["First paragraph\n\nSecond paragraph"])
        #expect(json["target"] as? String == "zh-CN")
        #expect(json["format"] as? String == "text")
    }

    @Test("Streaming chat requests opt into SSE")
    func streamingRequest() throws {
        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .openAICompatible,
            config: TranslationProviderConfiguration(
                apiKey: "sk-test",
                endpoint: "https://example.com/v1/chat/completions",
                model: "test-model"
            ),
            stream: true
        )

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["stream"] as? Bool == true)
    }

    @Test("Translation prompt protects document structure")
    func structurePreservingPrompt() throws {
        let request = try ProviderTranslationService.makeRequest(
            text: "Hello",
            target: "zh-Hans",
            provider: .openAICompatible,
            config: TranslationProviderConfiguration(apiKey: "sk-test", endpoint: "", model: "")
        )
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: String]])
        let prompt = try #require(messages.first?["content"])

        #expect(prompt.contains("paragraph count"))
        #expect(prompt.contains("line breaks"))
        #expect(prompt.contains("lists"))
        #expect(prompt.contains("code"))
        #expect(prompt.contains("URLs"))
    }

    @Test("Google Cloud responses expose text and detected language")
    func googleCloudResponse() throws {
        let data = Data(#"{"data":{"translations":[{"translatedText":"你好","detectedSourceLanguage":"en"}]}}"#.utf8)

        let result = try ProviderTranslationService.parseResponse(data, provider: .googleCloud)

        #expect(result.text == "你好")
        #expect(result.detectedSource == "en")
    }

    @Test("SSE parser distinguishes chat deltas from completion markers")
    func chatStreamEvents() throws {
        let delta = try ProviderTranslationService.parseStreamLine(
            #"data: {"choices":[{"delta":{"content":"你"}}]}"#
        )
        let done = try ProviderTranslationService.parseStreamLine("data: [DONE]")

        #expect(delta == .delta("你"))
        #expect(done == .done)
    }

    @Test("SSE framing rejects an oversized line before a newline arrives")
    func streamLineLimit() throws {
        var decoder = SSELineDecoder(maximumLineBytes: 4)

        for byte in Data("data".utf8) {
            #expect(try decoder.append(byte) == nil)
        }
        #expect(throws: ProviderTranslationError.responseTooLarge) {
            try decoder.append(UInt8(ascii: ":"))
        }
    }

    @Test("Streaming output has a total UTF-8 size bound")
    func streamOutputLimit() throws {
        var accumulator = TranslationStreamAccumulator(maximumUTF8Bytes: 4)

        #expect(try accumulator.append("ab") == "ab")
        #expect(throws: ProviderTranslationError.responseTooLarge) {
            try accumulator.append("你好")
        }
    }
}
