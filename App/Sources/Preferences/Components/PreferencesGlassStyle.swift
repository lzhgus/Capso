import SwiftUI
import AppKit

extension View {
    @ViewBuilder
    func preferencesGlassCard(cornerRadius: CGFloat = 10) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        self
            .background(
                shape.fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                shape.stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    func preferencesSidebarSelectionBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        self
            .background(
                shape.fill(
                    isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.18) :
                    isHovered ? Color(nsColor: .controlColor).opacity(0.5) : Color.clear
                )
            )
    }

    @ViewBuilder
    func preferencesGlassActionBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        self
            .background(
                shape.fill(isHovered ? Color(nsColor: .quaternaryLabelColor).opacity(0.6) : Color(nsColor: .controlColor))
            )
            .overlay(
                shape.stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            )
    }
}
