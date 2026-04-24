// Packages/TranslationKit/Tests/TranslationKitTests/TranslationServiceTests.swift
import Foundation
import Testing
import OCRKit
@testable import TranslationKit

actor FakeSession: TranslationSessioning {
    enum Scenario { case happy, unsupported, sessionThrows(Error) }
    var scenario: Scenario = .happy
    var installed = true
    var detectedSource = "en"
    var transform: @Sendable (String) -> String = { "【\($0)】" }

    func translate(_ sources: [String], from: String?, to target: String) async throws
        -> TranslationSessionResult
    {
        switch scenario {
        case .happy:
            return TranslationSessionResult(
                translations: sources.map(transform),
                detectedSource: detectedSource
            )
        case .unsupported:
            throw TranslationError.sourceUnsupported(language: "xx")
        case .sessionThrows(let e):
            throw TranslationError.sessionFailed(underlying: e)
        }
    }
    func status(from: String, to: String) async -> LanguagePairStatus {
        installed ? .installed : .supported
    }

    func setScenario(_ s: Scenario) { self.scenario = s }
    func setDetectedSource(_ d: String) { self.detectedSource = d }
}

@Suite("TranslationService")
struct TranslationServiceTests {
    private func sampleRegion(_ text: String) -> TextRegion {
        TextRegion(
            text: text,
            boundingBox: CGRect(x: 0, y: 0, width: 100, height: 20),
            confidence: 0.99
        )
    }

    @Test("happy path returns one translation per region")
    func happy() async throws {
        let fake = FakeSession()
        let service = TranslationService(session: fake)
        let regions = [sampleRegion("Hello"), sampleRegion("World")]
        let result = try await service.translate(regions: regions, target: "zh-Hans")
        #expect(result.count == 2)
        #expect(result[0].translation == "【Hello】")
        #expect(result[1].translation == "【World】")
    }

    @Test("filters empty-text regions before calling the session")
    func filtersEmpty() async throws {
        let fake = FakeSession()
        let service = TranslationService(session: fake)
        let regions = [sampleRegion("Hello"), sampleRegion("   "), sampleRegion("")]
        let result = try await service.translate(regions: regions, target: "zh-Hans")
        #expect(result.count == 1)
        #expect(result[0].original.text == "Hello")
    }

    @Test("rejects source == target with .sourceEqualsTarget")
    func sourceEqualsTarget() async throws {
        let fake = FakeSession()
        await fake.setDetectedSource("zh-Hans")
        let service = TranslationService(session: fake)
        do {
            _ = try await service.translate(regions: [sampleRegion("你好")], target: "zh-Hans")
            Issue.record("Expected throw")
        } catch let TranslationError.sourceEqualsTarget(lang) {
            #expect(lang == "zh-Hans")
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("propagates session-level errors")
    func sessionError() async throws {
        let fake = FakeSession()
        await fake.setScenario(.sessionThrows(NSError(domain: "x", code: 42)))
        let service = TranslationService(session: fake)
        do {
            _ = try await service.translate(regions: [sampleRegion("Hi")], target: "zh-Hans")
            Issue.record("Expected throw")
        } catch let TranslationError.sessionFailed(err as NSError) {
            #expect(err.code == 42)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }
}
