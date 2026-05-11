import AVFoundation
import EditorKit
import Foundation
import SharedKit

public enum CutExporter {
    public static func exportMP4(
        source: URL,
        trimRegions: [TrimRegion],
        quality: ExportQuality,
        destination: URL,
        progress: (@Sendable (Double) -> Void)? = nil,
        status: (@Sendable (ExportStatus) -> Void)? = nil
    ) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        let keptRanges = TrimRegion.keptRanges(duration: duration, removing: trimRegions)

        if keptRanges.count == 1,
           abs(keptRanges[0].start) < 0.01,
           abs(keptRanges[0].end - duration) < 0.01 {
            return try await MP4Exporter.export(
                source: source,
                quality: quality,
                destination: destination,
                progress: progress,
                status: status
            )
        }

        status?(ExportStatus(stage: .trimming, fractionCompleted: 0.08))
        let composition = AVMutableComposition()
        var cursor = CMTime.zero

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        if let sourceVideo = videoTracks.first,
           let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)
            for range in keptRanges {
                let cmRange = cmTimeRange(for: range)
                try videoTrack.insertTimeRange(cmRange, of: sourceVideo, at: cursor)
                cursor = cursor + cmRange.duration
            }
        }

        for sourceAudio in audioTracks {
            guard let audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }

            var audioCursor = CMTime.zero
            for range in keptRanges {
                let cmRange = cmTimeRange(for: range)
                try audioTrack.insertTimeRange(cmRange, of: sourceAudio, at: audioCursor)
                audioCursor = audioCursor + cmRange.duration
            }
        }

        let presetName = switch quality {
        case .maximum: AVAssetExportPresetHighestQuality
        case .social: AVAssetExportPreset1920x1080
        case .web: AVAssetExportPreset1280x720
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw ExportError.exportSessionFailed("Could not create cut export session")
        }

        try? FileManager.default.removeItem(at: destination)
        session.shouldOptimizeForNetworkUse = true
        status?(ExportStatus(stage: .encoding, fractionCompleted: 0.12))

        do {
            try await session.export(to: destination, as: .mp4)
        } catch is CancellationError {
            throw ExportError.cancelled
        } catch {
            throw ExportError.exportSessionFailed(error.localizedDescription)
        }

        status?(ExportStatus(stage: .finalizing, fractionCompleted: 1.0))
        progress?(1.0)
        return destination
    }

    private static func cmTimeRange(for range: TrimRegion.TimeRange) -> CMTimeRange {
        let start = CMTime(seconds: range.start, preferredTimescale: 600)
        let duration = CMTime(seconds: range.duration, preferredTimescale: 600)
        return CMTimeRange(start: start, duration: duration)
    }
}
