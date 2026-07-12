public enum QuickAccessActionKind: String, CaseIterable, Sendable {
    case drag
    case copy
    case save
    case upload
    case annotate
    case ocr
    case translate
    case pin
}

public enum QuickAccessActionLayout {
    public static func visibleActions(sharingAvailable: Bool) -> [QuickAccessActionKind] {
        var actions: [QuickAccessActionKind] = [.drag, .copy, .save]
        if sharingAvailable {
            actions.append(.upload)
        }
        actions.append(contentsOf: [.annotate, .pin])
        return actions
    }

    public static let overflowActions: [QuickAccessActionKind] = [.ocr, .translate]
}
