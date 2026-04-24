// App/Sources/Translation/TranslationLanguagePickerPopover.swift
import SwiftUI

struct TranslationLanguagePickerPopover: View {
    let current: String
    let available: [String]   // BCP-47 codes
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedLanguages, id: \.0) { code, name in
                        row(code: code, name: name, isSelected: code == current)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 320)

            footer
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Translate to")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(1.0)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
            Divider()
        }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            Text("Change default in Preferences")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private func row(code: String, name: String, isSelected: Bool) -> some View {
        Button(action: { onPick(code) }) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(name)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer(minLength: 8)
                Text(code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : Color.clear
            )
        }
        .buttonStyle(.plain)
    }

    private var sortedLanguages: [(String, String)] {
        let locale = Locale.current
        return available
            .map { code in (code, locale.localizedString(forIdentifier: code) ?? code) }
            .sorted { a, b in a.1.localizedCaseInsensitiveCompare(b.1) == .orderedAscending }
    }
}
