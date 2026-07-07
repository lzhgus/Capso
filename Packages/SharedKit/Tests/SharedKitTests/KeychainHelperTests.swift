// Packages/SharedKit/Tests/SharedKitTests/KeychainHelperTests.swift
import Testing
import Foundation
@testable import SharedKit

@Suite("KeychainHelper")
struct KeychainHelperTests {
    private let testService = "com.awesomemacapps.capso.test.\(UUID().uuidString)"

    @Test("write then read returns the value")
    func roundTrip() throws {
        let helper = KeychainHelper(service: testService)
        defer { try? helper.delete(account: "key") }

        try helper.set("hello", account: "key")
        #expect(try helper.get(account: "key") == "hello")
    }

    @Test("read returns nil when no entry exists")
    func missingReturnsNil() throws {
        let helper = KeychainHelper(service: testService)
        #expect(try helper.get(account: "missing") == nil)
    }

    @Test("set overwrites existing value")
    func overwrite() throws {
        let helper = KeychainHelper(service: testService)
        defer { try? helper.delete(account: "key") }

        try helper.set("first", account: "key")
        try helper.set("second", account: "key")
        #expect(try helper.get(account: "key") == "second")
    }

    @Test("delete removes the entry")
    func delete() throws {
        let helper = KeychainHelper(service: testService)
        defer { try? helper.delete(account: "key") }
        try helper.set("x", account: "key")
        try helper.delete(account: "key")
        #expect(try helper.get(account: "key") == nil)
    }

    @Test("delete on missing account does not throw")
    func deleteNonExistent() throws {
        let helper = KeychainHelper(service: testService)
        try helper.delete(account: "neverExisted")  // must not throw
    }
}
