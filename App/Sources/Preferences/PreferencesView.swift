// App/Sources/Preferences/PreferencesView.swift
import Combine
import SwiftUI

enum PreferencesTab: String, CaseIterable {
    case general
    case screenshots
    case recording
    case quickAccess
    case cloudShare
    case export
    case ocr
    case shortcuts

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .screenshots: "Screenshots"
        case .recording: "Recording"
        case .quickAccess: "Quick Access"
        case .cloudShare: "Cloud Share"
        case .export: "Export"
        case .ocr: "Text & Translation"
        case .shortcuts: "Shortcuts"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .screenshots: "camera"
        case .recording: "record.circle"
        case .quickAccess: "bolt"
        case .cloudShare: "icloud"
        case .export: "folder"
        case .ocr: "text.viewfinder"
        case .shortcuts: "keyboard"
        }
    }
}

struct PreferencesView: View {
    @State private var selectedTab: PreferencesTab
    let viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    init(viewModel: PreferencesViewModel, updateManager: UpdateManager?, initialTab: PreferencesTab? = nil) {
        self.viewModel = viewModel
        self.updateManager = updateManager
        self._selectedTab = State(initialValue: initialTab ?? .general)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
                .background(Color.white.opacity(0.06))
            content
        }
        .frame(width: 680, height: 480)
        .onReceive(NotificationCenter.default.publisher(for: .openScreenshotSettings)) { notification in
            if let tab = notification.object as? PreferencesTab {
                selectedTab = tab
            } else {
                selectedTab = .screenshots
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preferencesSwitchTab)) { notification in
            if let tab = notification.object as? PreferencesTab {
                selectedTab = tab
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 2) {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                SidebarButton(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
            }
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(width: 180)
        .background(Color.white.opacity(0.04))
    }

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch selectedTab {
                case .general:
                    GeneralSettingsView(viewModel: viewModel, updateManager: updateManager)
                case .screenshots:
                    ScreenshotSettingsView(viewModel: viewModel)
                case .recording:
                    RecordingSettingsView(viewModel: viewModel)
                case .quickAccess:
                    QuickAccessSettingsView(viewModel: viewModel)
                case .cloudShare:
                    CloudShareSettingsView(viewModel: viewModel)
                case .export:
                    ExportSettingsView(viewModel: viewModel)
                case .ocr:
                    TextAndTranslationSettingsView(viewModel: viewModel)
                case .shortcuts:
                    ShortcutSettingsView()
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SidebarButton: View {
    let tab: PreferencesTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                    .font(.system(size: 14))
                    .opacity(isSelected ? 1 : 0.7)
                Text(tab.title)
                    .font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        isSelected ? Color.white.opacity(0.12) :
                        isHovered ? Color.white.opacity(0.08) : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
        .onHover { isHovered = $0 }
    }
}
