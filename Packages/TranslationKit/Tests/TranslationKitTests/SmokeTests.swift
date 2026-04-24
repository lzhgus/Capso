import Testing
@testable import TranslationKit

@Suite("TranslationKit")
struct TranslationKitSmokeTests {
    @Test("Module compiles")
    func compiles() {
        #expect(true)
    }
}
