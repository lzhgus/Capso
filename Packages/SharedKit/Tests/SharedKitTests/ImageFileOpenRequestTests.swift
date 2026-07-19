import Foundation
import Testing
@testable import SharedKit

@Suite("ImageFileOpenRequest")
struct ImageFileOpenRequestTests {
    @Test("partition splits image files from other URLs")
    func partitionSplitsImageFilesFromOtherURLs() throws {
        let photo = URL(fileURLWithPath: "/tmp/photo.png")
        let automation = try #require(URL(string: "capso://grab/area"))
        let notes = URL(fileURLWithPath: "/tmp/notes.txt")

        let result = ImageFileOpenRequest.partition(urls: [photo, automation, notes])

        #expect(result.imageFiles == [photo])
        #expect(result.remainder == [automation, notes])
    }

    @Test("partition of empty list is empty")
    func partitionOfEmptyListIsEmpty() {
        let result = ImageFileOpenRequest.partition(urls: [])
        #expect(result.imageFiles.isEmpty)
        #expect(result.remainder.isEmpty)
    }
}

@Suite("ImageFileOpenBuffer")
struct ImageFileOpenBufferTests {
    @Test("buffer holds URLs until the coordinator is ready")
    func bufferHoldsURLsUntilCoordinatorReady() {
        var buffer = ImageFileOpenBuffer()
        let urls = [URL(fileURLWithPath: "/tmp/a.png")]
        buffer.enqueue(urls)

        #expect(buffer.takeIfReady(coordinatorIsReady: false) == nil)
        #expect(buffer.takeIfReady(coordinatorIsReady: true) == urls)
        #expect(buffer.takeIfReady(coordinatorIsReady: true) == nil)
    }

    @Test("buffer appends a second batch instead of dropping it")
    func bufferAppendsSecondBatch() {
        var buffer = ImageFileOpenBuffer()
        let first = [URL(fileURLWithPath: "/tmp/a.png")]
        let second = [URL(fileURLWithPath: "/tmp/b.png")]
        buffer.enqueue(first)
        buffer.enqueue(second)

        #expect(buffer.takeIfReady(coordinatorIsReady: true) == first + second)
    }
}
