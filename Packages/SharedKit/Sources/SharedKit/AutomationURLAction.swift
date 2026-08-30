import Foundation

public enum AutomationURLAction: Equatable, Sendable {
    case captureArea
    case captureFullscreen
    case captureWindow
    case captureAllInOne
    case captureScrolling
    case captureSelfTimer
    case captureLastArea
    case captureAreaToClipboard
    case captureAreaAndShare
    case captureAreaAndAnnotate
    case pinFromClipboard
    case editClipboardImage
    case openImageFile
    case captureOCR
    case captureAndTranslate
    case translateSelectedText
    case translateTypedText
    case recordArea
    case recordFullscreen
    case openHistory
    case openPreferences

    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.caseInsensitiveCompare("capso") == .orderedSame,
              components.host?.caseInsensitiveCompare("grab") == .orderedSame,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.percentEncodedQuery == nil,
              components.fragment == nil else {
            return nil
        }

        switch components.percentEncodedPath {
        case "/area": self = .captureArea
        case "/fullscreen": self = .captureFullscreen
        case "/window": self = .captureWindow
        case "/all-in-one": self = .captureAllInOne
        case "/scrolling": self = .captureScrolling
        case "/self-timer": self = .captureSelfTimer
        case "/last-area": self = .captureLastArea
        case "/clipboard", "/area-to-clipboard": self = .captureAreaToClipboard
        case "/share", "/area-and-share": self = .captureAreaAndShare
        case "/annotate", "/area-and-annotate": self = .captureAreaAndAnnotate
        case "/pin", "/pin-from-clipboard": self = .pinFromClipboard
        case "/edit-clipboard", "/edit-clipboard-image": self = .editClipboardImage
        case "/open-image", "/open-image-file": self = .openImageFile
        case "/ocr", "/text", "/capture-text": self = .captureOCR
        case "/translate", "/capture-and-translate": self = .captureAndTranslate
        case "/translate-selection", "/translate-selected-text": self = .translateSelectedText
        case "/translate-text", "/translate-typed-text": self = .translateTypedText
        case "/record", "/record-area", "/record-screen": self = .recordArea
        case "/record-fullscreen", "/record-full-screen": self = .recordFullscreen
        case "/history", "/screenshot-history": self = .openHistory
        case "/preferences", "/settings": self = .openPreferences
        default: return nil
        }
    }
}

public struct AutomationURLRequestBuffer: Sendable {
    private var pendingAction: AutomationURLAction?

    public init() {}

    public mutating func enqueue(_ action: AutomationURLAction) {
        guard pendingAction == nil else { return }
        pendingAction = action
    }

    public mutating func takeIfReady(
        coordinatorIsReady: Bool,
        captureSelectionIsActive: Bool
    ) -> AutomationURLAction? {
        guard coordinatorIsReady, let action = pendingAction else { return nil }
        pendingAction = nil
        guard !captureSelectionIsActive else { return nil }
        return action
    }
}
