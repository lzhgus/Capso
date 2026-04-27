// Packages/ShareKit/Tests/ShareKitTests/IDGeneratorTests.swift

import Testing
import Foundation
@testable import ShareKit

@Suite("IDGenerator")
struct IDGeneratorTests {
    @Test("generates 7-char IDs")
    func length() {
        #expect(IDGenerator.shortID().count == 7)
    }

    @Test("uses base32 charset only")
    func charset() {
        let allowed = Set("0123456789abcdefghijklmnopqrstuv")
        let id = IDGenerator.shortID()
        #expect(id.allSatisfy { allowed.contains($0) })
    }

    @Test("produces unique IDs over 1k iterations")
    func uniqueness() {
        var seen = Set<String>()
        for _ in 0..<1_000 {
            seen.insert(IDGenerator.shortID())
        }
        #expect(seen.count == 1_000)
    }
}
