import ExportKit
import RecordingKit
import UniformTypeIdentifiers

enum EditorOutputFormat: Equatable, Sendable {
    case mp4
    case gif

    init(recordingFormat: RecordingKit.RecordingFormat) {
        self = recordingFormat == .gif ? .gif : .mp4
    }

    var exportFormat: ExportFormat {
        switch self {
        case .mp4: .mp4
        case .gif: .gif
        }
    }

    var contentType: UTType {
        switch self {
        case .mp4: .mpeg4Movie
        case .gif: .gif
        }
    }

    var fileExtension: String {
        switch self {
        case .mp4: "mp4"
        case .gif: "gif"
        }
    }

    var defaultFilename: String {
        "Recording.\(fileExtension)"
    }
}
