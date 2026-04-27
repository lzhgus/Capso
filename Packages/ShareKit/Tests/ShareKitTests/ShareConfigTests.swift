// Packages/ShareKit/Tests/ShareKitTests/ShareConfigTests.swift

import Testing
import Foundation
@testable import ShareKit

@Suite("ShareConfig")
struct ShareConfigTests {
    @Test("composeURL preserves extension and inserts ID")
    func compose() {
        let url = ShareConfig.composePublicURL(prefix: "https://share.example.com/", id: "abc1234", ext: "png")
        #expect(url.absoluteString == "https://share.example.com/abc1234.png")
    }

    @Test("composeURL handles prefix without trailing slash")
    func noTrailingSlash() {
        let url = ShareConfig.composePublicURL(prefix: "https://share.example.com", id: "xyz5678", ext: "mp4")
        #expect(url.absoluteString == "https://share.example.com/xyz5678.mp4")
    }

    @Test("normalizePrefix strips trailing slash")
    func normalize() {
        #expect(ShareConfig.normalizePrefix("https://x.com/") == "https://x.com")
        #expect(ShareConfig.normalizePrefix("https://x.com") == "https://x.com")
    }

    @Test("validatePrefix rejects http")
    func rejectsHTTP() {
        #expect(throws: ShareError.self) {
            try ShareConfig.validatePrefix("http://x.com")
        }
    }

    @Test("validatePrefix accepts https")
    func acceptsHTTPS() throws {
        try ShareConfig.validatePrefix("https://share.example.com")
    }

    @Test("validatePrefix rejects hostless URL")
    func rejectsHostless() {
        #expect(throws: ShareError.self) {
            try ShareConfig.validatePrefix("https://")
        }
        #expect(throws: ShareError.self) {
            try ShareConfig.validatePrefix("https:///")
        }
    }

    @Test("validatePrefix rejects query strings and fragments")
    func rejectsQueryFragment() {
        #expect(throws: ShareError.self) {
            try ShareConfig.validatePrefix("https://x.com?foo=bar")
        }
        #expect(throws: ShareError.self) {
            try ShareConfig.validatePrefix("https://x.com#frag")
        }
    }

    @Test("normalizePrefix strips multiple trailing slashes")
    func normalizeMultipleSlashes() {
        #expect(ShareConfig.normalizePrefix("https://x.com//") == "https://x.com")
        #expect(ShareConfig.normalizePrefix("https://x.com///") == "https://x.com")
    }
}
