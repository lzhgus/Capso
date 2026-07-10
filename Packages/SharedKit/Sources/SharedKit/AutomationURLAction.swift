import Foundation

public enum AutomationURLAction: Equatable, Sendable {
    case captureArea
    case captureFullscreen
    case captureWindow

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
