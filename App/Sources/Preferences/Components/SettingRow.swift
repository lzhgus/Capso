import SwiftUI

struct SettingRow<Control: View>: View {
    let label: LocalizedStringKey
    var sublabel: LocalizedStringKey? = nil
    var showDivider: Bool = false
    @ViewBuilder let control: Control

    var body: some View {
        VStack(spacing: 0) {
            if showDivider {
                Divider()
                    .background(Color.white.opacity(0.06))
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                    if let sublabel {
                        Text(sublabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                control
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 40)
        }
    }
}
