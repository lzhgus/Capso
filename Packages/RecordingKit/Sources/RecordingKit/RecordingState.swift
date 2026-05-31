// Packages/RecordingKit/Sources/RecordingKit/RecordingState.swift
import Foundation
import CoreGraphics

public enum RecordingState: String, Sendable {
    case idle
    case preparing
    case recording
    case paused
    case stopping

    public var isActive: Bool {
        self == .recording || self == .paused
    }
}

public enum RecordingFormat: String, Sendable {
    case video
    case gif
}

public enum RecordingTarget: Sendable, Equatable {
    case displayArea(displayID: CGDirectDisplayID, rect: CGRect)
    case window(windowID: CGWindowID)
}

public struct RecordingConfig: Sendable {
    public let target: RecordingTarget
    public var format: RecordingFormat
    public var fps: Int
    public var captureSystemAudio: Bool
    public var captureMicrophone: Bool
    public var showCursor: Bool

    public init(
        captureRect: CGRect,
        displayID: CGDirectDisplayID,
        format: RecordingFormat = .video,
        fps: Int = 30,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false,
        showCursor: Bool = true
    ) {
        self.target = .displayArea(displayID: displayID, rect: captureRect)
        self.format = format
        self.fps = fps
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.showCursor = showCursor
    }

    public init(
        windowID: CGWindowID,
        format: RecordingFormat = .video,
        fps: Int = 30,
        captureSystemAudio: Bool = true,
        captureMicrophone: Bool = false,
        showCursor: Bool = true
    ) {
        self.target = .window(windowID: windowID)
        self.format = format
        self.fps = fps
        self.captureSystemAudio = captureSystemAudio
        self.captureMicrophone = captureMicrophone
        self.showCursor = showCursor
    }
}

public struct RecordingResult: Sendable {
    public let fileURL: URL
    public let duration: TimeInterval
    public let format: RecordingFormat
    public let size: CGSize

    public init(fileURL: URL, duration: TimeInterval, format: RecordingFormat, size: CGSize) {
        self.fileURL = fileURL
        self.duration = duration
        self.format = format
        self.size = size
    }
}
