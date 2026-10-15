// App/Sources/Preferences/PreferencesView.swift
import Combine
import SwiftUI
import AppKit

enum PreferencesTab: String, CaseIterable, Identifiable, Sendable {
    case general
    case permissions
    case screenshots
    case recording
    case quickAccess
    case cloudShare
    case export
    case ocr
    case shortcuts

    var id: String { rawValue }

    var title: LocalizedStringKey {
        LocalizedStringKey(displayTitle)
    }

    var displayTitle: String {
        switch self {
        case .general: String(localized: "General")
        case .permissions: String(localized: "Permissions")
        case .screenshots: String(localized: "Screenshots")
        case .recording: String(localized: "Recording")
        case .quickAccess: String(localized: "Quick Access")
        case .cloudShare: String(localized: "Cloud Share")
        case .export: String(localized: "Export")
        case .ocr: String(localized: "Text & Translation")
        case .shortcuts: String(localized: "Shortcuts")
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .permissions: "lock.shield"
        case .screenshots: "camera"
        case .recording: "record.circle"
        case .quickAccess: "bolt"
        case .cloudShare: "icloud"
        case .export: "folder"
        case .ocr: "text.viewfinder"
        case .shortcuts: "keyboard"
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: .gray
        case .permissions: .blue
        case .screenshots: .indigo
        case .recording: .red
        case .quickAccess: .orange
        case .cloudShare: .cyan
        case .export: .teal
        case .ocr: .green
        case .shortcuts: .purple
        }
    }
}

enum PreferencesSidebarItem: Hashable, Identifiable {
    case tab(PreferencesTab)
    case searchResult(SettingSearchItem)

    var id: String {
        switch self {
        case .tab(let tab): return "tab-\(tab.rawValue)"
        case .searchResult(let item): return "search-\(item.id)"
        }
    }

    var targetTab: PreferencesTab {
        switch self {
        case .tab(let tab): return tab
        case .searchResult(let item): return item.tab
        }
    }
}

struct PreferencesView: View {
    @State private var selectedSidebarItem: PreferencesSidebarItem?
    @State private var activeTab: PreferencesTab = .general
    @State private var searchText = ""
    @State private var highlightedItemId: String? = nil
    let viewModel: PreferencesViewModel
    let updateManager: UpdateManager?

    init(viewModel: PreferencesViewModel, updateManager: UpdateManager?, initialTab: PreferencesTab? = nil) {
        self.viewModel = viewModel
        self.updateManager = updateManager
        let tab = initialTab ?? .general
        self._activeTab = State(initialValue: tab)
        self._selectedSidebarItem = State(initialValue: .tab(tab))
    }

    private var currentTab: PreferencesTab {
        selectedSidebarItem?.targetTab ?? activeTab
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var matchingSearchItems: [SettingSearchItem] {
        SettingSearchIndex.items.filter { $0.matches(query: searchText) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSidebarItem) {
                if !isSearching {
                    ForEach(PreferencesTab.allCases) { tab in
                        NavigationLink(value: PreferencesSidebarItem.tab(tab)) {
                            HStack(spacing: 10) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(tab.badgeColor.gradient, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
                                Text(tab.title)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .layoutPriority(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } else {
                    ForEach(matchingSearchItems) { item in
                        NavigationLink(value: PreferencesSidebarItem.searchResult(item)) {
                            HStack(spacing: 8) {
                                Image(systemName: item.tab.icon)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 18, height: 18)
                                    .background(item.tab.badgeColor.gradient, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.breadcrumb)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 190, max: 190)
            .searchable(text: $searchText, placement: .sidebar, prompt: Text("Search"))
            .toolbar(removing: .sidebarToggle)
            .overlay {
                if isSearching && matchingSearchItems.isEmpty {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 34))
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                        Text("No results")
                            .font(.system(size: 13, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                        Text("Check the spelling or try a\nnew search.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
        } detail: {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    tabView(for: activeTab)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle(activeTab.displayTitle)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Spacer()
                    }
                }
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.highlightedSettingId, highlightedItemId)
                .onChange(of: highlightedItemId) { _, newId in
                    guard let newId else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            scrollProxy.scrollTo(newId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: .infinity, minHeight: 480, idealHeight: 560, maxHeight: .infinity)
        .background {
            SplitViewConfigurator()
        }
        .onChange(of: selectedSidebarItem) { _, newValue in
            if case .searchResult(let item) = newValue {
                activeTab = item.tab
                if highlightedItemId == item.id {
                    highlightedItemId = nil
                    DispatchQueue.main.async {
                        highlightedItemId = item.id
                    }
                } else {
                    highlightedItemId = item.id
                }
            } else if let target = newValue?.targetTab {
                activeTab = target
                highlightedItemId = nil
            }
        }
        .onChange(of: searchText) { _, newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                selectedSidebarItem = .tab(activeTab)
                highlightedItemId = nil
            } else {
                selectedSidebarItem = nil
                highlightedItemId = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openScreenshotSettings)) { notification in
            let tab = (notification.object as? PreferencesTab) ?? .screenshots
            searchText = ""
            activeTab = tab
            selectedSidebarItem = .tab(tab)
            highlightedItemId = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .preferencesSwitchTab)) { notification in
            if let tab = notification.object as? PreferencesTab {
                searchText = ""
                activeTab = tab
                selectedSidebarItem = .tab(tab)
                highlightedItemId = nil
            }
        }
    }

    @ViewBuilder
    private func tabView(for tab: PreferencesTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(viewModel: viewModel, updateManager: updateManager)
        case .permissions:
            PermissionSettingsView(viewModel: viewModel)
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
            ShortcutSettingsView(viewModel: viewModel)
        }
    }
}

/// Disables collapsing the sidebar on mouse drag and enforces the minimum sidebar width
private struct SplitViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            configureSplitView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            configureSplitView(from: nsView)
        }
    }

    private func configureSplitView(from view: NSView) {
        guard let window = view.window else { return }
        
        // Find NSSplitViewController in the window's controller hierarchy
        if let splitViewController = findSplitViewController(in: window.contentViewController) {
            if let sidebarItem = splitViewController.splitViewItems.first {
                sidebarItem.canCollapse = false
                sidebarItem.minimumThickness = 190
                sidebarItem.maximumThickness = 190
            }
        }
    }

    private func findSplitViewController(in vc: NSViewController?) -> NSSplitViewController? {
        guard let vc else { return nil }
        if let svc = vc as? NSSplitViewController { return svc }
        for child in vc.children {
            if let svc = findSplitViewController(in: child) { return svc }
        }
        return nil
    }
}
