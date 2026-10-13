// Packages/ShareKit/Tests/ShareKitTests/ShareCoordinatorTests.swift

import Testing
import Foundation
import AppKit
@testable import ShareKit

@Suite("ShareCoordinator", .serialized)
@MainActor
struct ShareCoordinatorTests {
    actor StubDestination: ShareDestination {
        var shouldFail: ShareError?
        var lastContentType: String?
        func setShouldFail(_ err: ShareError?) { shouldFail = err }

        func upload(file: URL, key: String, contentType: String) async throws -> URL {
            lastContentType = contentType
            if let err = shouldFail { throw err }
            return URL(string: "https://stub/\(key)")!
        }
        func delete(key: String) async throws {
            if let err = shouldFail { throw err }
        }
        nonisolated func publicURL(for key: String) -> URL { URL(string: "https://stub/\(key)")! }
        func validateConfig() async throws {
            if let err = shouldFail { throw err }
        }
    }

    actor BlockingDestination: ShareDestination {
        private let failFirst: Bool
        private var started: [String] = []
        private var firstStarted = false
        private var firstStartedWaiters: [CheckedContinuation<Void, Never>] = []
        private var releaseFirstContinuation: CheckedContinuation<Void, Never>?

        init(failFirst: Bool = false) {
            self.failFirst = failFirst
        }

        func upload(file: URL, key: String, contentType: String) async throws -> URL {
            let callIndex = started.count
            started.append(file.lastPathComponent)

            if callIndex == 0 {
                firstStarted = true
                firstStartedWaiters.forEach { $0.resume() }
                firstStartedWaiters.removeAll()
                await withCheckedContinuation { continuation in
                    releaseFirstContinuation = continuation
                }
                if failFirst {
                    throw ShareError.network(underlying: "first failed")
                }
            }

            return URL(string: "https://stub/\(file.lastPathComponent)")!
        }

        func delete(key: String) async throws {}
        func validateConfig() async throws {}
        nonisolated func publicURL(for key: String) -> URL { URL(string: "https://stub/\(key)")! }

        func waitUntilFirstStarts() async {
            if firstStarted { return }
            await withCheckedContinuation { continuation in
                firstStartedWaiters.append(continuation)
            }
        }

        func releaseFirst() {
            releaseFirstContinuation?.resume()
            releaseFirstContinuation = nil
        }

        func startedFiles() -> [String] {
            started
        }
    }

    @Test("starts idle")
    func startsIdle() {
        let coord = ShareCoordinator(destination: StubDestination())
        if case .idle = coord.state {} else { Issue.record("expected idle, got \(coord.state)") }
    }

    @Test("upload success transitions idle → uploading → succeeded")
    func successPath() async throws {
        let stub = StubDestination()
        let coord = ShareCoordinator(destination: stub)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let url = try await coord.upload(file: tmp, contentType: "image/png")
        #expect(url.absoluteString.hasPrefix("https://stub/"))
        if case .succeeded(let u) = coord.state { #expect(u == url) } else {
            Issue.record("expected succeeded, got \(coord.state)")
        }
    }

    @Test("upload network failure transitions to failed")
    func failurePath() async throws {
        let stub = StubDestination()
        await stub.setShouldFail(.network(underlying: "boom"))
        let coord = ShareCoordinator(destination: stub)

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
        try Data([0]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        await #expect(throws: ShareError.self) {
            try await coord.upload(file: tmp, contentType: "image/png")
        }
        if case .failed = coord.state {} else {
            Issue.record("expected failed, got \(coord.state)")
        }
    }

    @Test("reset from succeeded returns to idle")
    func resetFromSucceeded() async throws {
        let stub = StubDestination()
        let coord = ShareCoordinator(destination: stub)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
        try Data([0x89]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try await coord.upload(file: tmp, contentType: "image/png")
        if case .succeeded = coord.state {} else {
            Issue.record("expected succeeded before reset, got \(coord.state)")
        }

        coord.reset()
        if case .idle = coord.state {} else {
            Issue.record("expected idle after reset, got \(coord.state)")
        }
    }

    @Test("reset from failed returns to idle")
    func resetFromFailed() async throws {
        let stub = StubDestination()
        await stub.setShouldFail(.network(underlying: "boom"))
        let coord = ShareCoordinator(destination: stub)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
        try Data([0]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try? await coord.upload(file: tmp, contentType: "image/png")
        if case .failed = coord.state {} else {
            Issue.record("expected failed before reset, got \(coord.state)")
        }

        coord.reset()
        if case .idle = coord.state {} else {
            Issue.record("expected idle after reset, got \(coord.state)")
        }
    }

    @Test("contentType is forwarded to destination")
    func contentTypeIsForwarded() async throws {
        let stub = StubDestination()
        let coord = ShareCoordinator(destination: stub)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
        try Data([0x89]).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        _ = try await coord.upload(file: tmp, contentType: "image/png")
        let received = await stub.lastContentType
        #expect(received == "image/png")
    }

    @Test("concurrent uploads are processed in FIFO order")
    func concurrentUploadsAreSerialized() async throws {
        let destination = BlockingDestination()
        let coord = ShareCoordinator(destination: destination)
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("first-\(UUID().uuidString).png")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("second-\(UUID().uuidString).png")

        let first = Task { @MainActor in
            try await coord.upload(file: firstURL, contentType: "image/png")
        }
        await destination.waitUntilFirstStarts()

        let second = Task { @MainActor in
            try await coord.upload(file: secondURL, contentType: "image/png")
        }
        await Task.yield()

        #expect(await destination.startedFiles() == [firstURL.lastPathComponent])

        await destination.releaseFirst()
        _ = try await first.value
        _ = try await second.value

        #expect(await destination.startedFiles() == [
            firstURL.lastPathComponent,
            secondURL.lastPathComponent,
        ])
    }

    @Test("a failed upload does not block the next queued upload")
    func failedUploadDoesNotBlockQueue() async throws {
        let destination = BlockingDestination(failFirst: true)
        let coord = ShareCoordinator(destination: destination)
        let firstURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("first-failure-\(UUID().uuidString).png")
        let secondURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("second-success-\(UUID().uuidString).png")

        let first = Task { @MainActor in
            try await coord.upload(file: firstURL, contentType: "image/png")
        }
        await destination.waitUntilFirstStarts()
        let second = Task { @MainActor in
            try await coord.upload(file: secondURL, contentType: "image/png")
        }

        await destination.releaseFirst()

        await #expect(throws: ShareError.self) {
            try await first.value
        }
        _ = try await second.value
        #expect(await destination.startedFiles() == [
            firstURL.lastPathComponent,
            secondURL.lastPathComponent,
        ])
    }

    @Test("upload attempt gate rejects duplicates until the active attempt finishes")
    func uploadAttemptGateRejectsDuplicates() {
        var gate = UploadAttemptGate()

        let firstStarted = gate.begin()
        let duplicateStarted = gate.begin()
        #expect(firstStarted)
        #expect(!duplicateStarted)

        gate.finish()
        let retryStarted = gate.begin()
        #expect(retryStarted)
    }

    @Test("Copy-when-upload-starts puts the link on the clipboard while the upload is still running")
    func copiesLinkWhenUploadStarts() async throws {
        let destination = BlockingDestination()
        let coord = ShareCoordinator(destination: destination) { true }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("before", forType: .string)

        let upload = Task { @MainActor in
            try await coord.upload(file: URL(fileURLWithPath: "/tmp/shot.png"), contentType: "image/png")
        }
        await destination.waitUntilFirstStarts()
        let early = try #require(NSPasteboard.general.string(forType: .string))
        #expect(early.hasPrefix("https://stub/") && early.hasSuffix(".png"))

        await destination.releaseFirst()
        _ = try await upload.value
        #expect(NSPasteboard.general.string(forType: .string) == early)
    }

    @Test("By default the link is only copied once the upload finishes")
    func copiesLinkAfterUploadByDefault() async throws {
        let destination = BlockingDestination()
        let coord = ShareCoordinator(destination: destination)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("before", forType: .string)

        let upload = Task { @MainActor in
            try await coord.upload(file: URL(fileURLWithPath: "/tmp/shot.png"), contentType: "image/png")
        }
        await destination.waitUntilFirstStarts()
        #expect(NSPasteboard.general.string(forType: .string) == "before")

        await destination.releaseFirst()
        let url = try await upload.value
        #expect(NSPasteboard.general.string(forType: .string) == url.absoluteString)
    }

    @Test("Every provider knows its public URL before uploading", arguments: [
        ShareConfig(provider: .r2, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["accountID": "abc123", "pathPrefix": "shots"]),
        ShareConfig(provider: .s3, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["region": "us-east-1", "pathPrefix": "shots"]),
        ShareConfig(provider: .tencentCOS, urlPrefix: "https://cdn.example.com", bucket: "capso-123456", fields: ["region": "ap-guangzhou", "pathPrefix": "shots"]),
        ShareConfig(provider: .aliyunOSS, urlPrefix: "https://cdn.example.com", bucket: "capso", fields: ["region": "oss-cn-hangzhou", "pathPrefix": "shots"]),
    ])
    func publicURLBeforeUpload(config: ShareConfig) throws {
        let destination = try ShareDestinationFactory.make(config: config, accessKey: "AK", secretKey: "SK")
        #expect(destination.publicURL(for: "Ab3x9.png").absoluteString == "https://cdn.example.com/shots/Ab3x9.png")
    }
}
