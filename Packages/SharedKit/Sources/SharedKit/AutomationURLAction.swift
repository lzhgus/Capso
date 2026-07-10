import Foundation

public enum AutomationURLAction: Equatable, Sendable {
    case captureArea
    case captureFullscreen
    case captureWindow

    public init?(url: URL) {
        guard url.scheme?.caseInsensitiveCompare("capso") == .orderedSame,
              url.host?.caseInsensitiveCompare("grab") == .orderedSame,
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            return nil
        }

        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count == 1 else { return nil }

        switch pathComponents[0] {
        case "area": self = .captureArea
        case "fullscreen": self = .captureFullscreen
        case "window": self = .captureWindow
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
