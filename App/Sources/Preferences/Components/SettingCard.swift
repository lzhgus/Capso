import SwiftUI

struct SettingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .preferencesGlassCard()
    }
}

struct SettingGroup<Content: View, Trailing: View>: View {
    let title: LocalizedStringKey
    let trailing: Trailing
    @ViewBuilder let content: Content

    init(
        title: LocalizedStringKey,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .padding(.leading, 2)
                Spacer()
                trailing
            }
            content
        }
    }
}

extension SettingGroup where Trailing == EmptyView {
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

// MARK: - Search Highlight & Scroll Target

struct HighlightedSettingIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var highlightedSettingId: String? {
        get { self[HighlightedSettingIdKey.self] }
        set { self[HighlightedSettingIdKey.self] = newValue }
    }
}

struct SettingSearchHighlightModifier: ViewModifier {
    let id: String
    @Environment(\.highlightedSettingId) private var highlightedSettingId
    @State private var isHighlighted: Bool = false
    @State private var fadeWorkItem: DispatchWorkItem? = nil

    func body(content: Content) -> some View {
        content
            .id(id)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isHighlighted ? 0.22 : 0))
                    .padding(1)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(isHighlighted ? 0.95 : 0), lineWidth: 2)
                    .padding(1)
                    .shadow(color: Color.accentColor.opacity(isHighlighted ? 0.45 : 0), radius: 4)
                    .allowsHitTesting(false)
            )
            .animation(.easeInOut(duration: 0.25), value: isHighlighted)
            .onAppear {
                if highlightedSettingId == id {
                    triggerHighlight()
                }
            }
            .onChange(of: highlightedSettingId) { _, newId in
                if newId == id {
                    triggerHighlight()
                } else if isHighlighted {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isHighlighted = false
                    }
                }
            }
    }

    private func triggerHighlight() {
        fadeWorkItem?.cancel()
        withAnimation(.easeOut(duration: 0.25)) {
            isHighlighted = true
        }
        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.8)) {
                isHighlighted = false
            }
        }
        fadeWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}

extension View {
    func searchHighlightTarget(_ id: String) -> some View {
        modifier(SettingSearchHighlightModifier(id: id))
    }
}
