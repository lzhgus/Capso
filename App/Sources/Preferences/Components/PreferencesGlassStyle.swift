import SwiftUI

extension View {
    @ViewBuilder
    func preferencesGlassCard(cornerRadius: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .glassEffect(.regular.tint(Color.white.opacity(0.04)), in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            self
                .background(Color.white.opacity(0.04), in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
#else
        self
            .background(Color.white.opacity(0.04), in: shape)
            .overlay(
                shape.stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )
#endif
    }

    @ViewBuilder
    func preferencesSidebarSelectionBackground(isSelected: Bool, isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

#if compiler(>=6.2)
        if #available(macOS 26.0, *), isSelected || isHovered {
            self
                .background(
                    shape.fill(Color.white.opacity(isSelected ? 0.06 : 0.03))
                )
                .glassEffect(
                    .regular.tint(Color.white.opacity(isSelected ? 0.08 : 0.04)).interactive(),
                    in: shape
                )
        } else {
            self
                .background(
                    shape.fill(
                        isSelected ? Color.white.opacity(0.12) :
                        isHovered ? Color.white.opacity(0.08) : Color.clear
                    )
                )
        }
#else
        self
            .background(
                shape.fill(
                    isSelected ? Color.white.opacity(0.12) :
                    isHovered ? Color.white.opacity(0.08) : Color.clear
                )
            )
#endif
    }

    @ViewBuilder
    func preferencesGlassActionBackground(isHovered: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self
                .background(
                    shape.fill(Color.white.opacity(isHovered ? 0.05 : 0.025))
                )
                .glassEffect(.regular.tint(Color.white.opacity(0.05)).interactive(), in: shape)
                .overlay(
                    shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        } else {
            self
                .background(
                    shape.fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                )
                .overlay(
                    shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        }
#else
        self
            .background(
                shape.fill(isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )
#endif
    }
}
