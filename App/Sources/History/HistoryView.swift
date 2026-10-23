// App/Sources/History/HistoryView.swift
import SwiftUI
import HistoryKit

struct HistoryView: View {
    let coordinator: HistoryCoordinator
    var onQuickLook: ([URL]) -> Void = { _ in }

    @State private var selection: Set<UUID> = []
    @State private var anchorID: UUID?
    @State private var columns = 1
    @FocusState private var isGridFocused: Bool

    private var groupedEntries: [(String, [HistoryEntry])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [String: [HistoryEntry]] = [:]
        var order: [String] = []

        for entry in coordinator.entries {
            let key: String
            if calendar.isDateInToday(entry.createdAt) {
                key = String(localized: "Today")
            } else if calendar.isDateInYesterday(entry.createdAt) {
                key = String(localized: "Yesterday")
            } else if let daysAgo = calendar.dateComponents([.day], from: entry.createdAt, to: now).day, daysAgo < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = "EEEE" // Day of week
                key = formatter.string(from: entry.createdAt)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMM d, yyyy"
                key = formatter.string(from: entry.createdAt)
            }

            if groups[key] == nil {
                order.append(key)
            }
            groups[key, default: []].append(entry)
        }

        return order.compactMap { key in
            guard let entries = groups[key] else { return nil }
            return (key, entries)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            filterBar
            Divider()

            // Content
            if coordinator.entries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(groupedEntries, id: \.0) { section, entries in
                                sectionView(title: section, count: entries.count, entries: entries)
                            }
                        }
                        .padding(16)
                        .background(GeometryReader { geo in
                            Color.clear.onAppear { updateColumns(geo.size.width) }
                                .onChange(of: geo.size.width) { _, width in updateColumns(width) }
                        })
                    }
                    .focusable()
                    .focused($isGridFocused)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                        moveSelection(press.key, extending: press.modifiers.contains(.shift))
                        if let anchorID { proxy.scrollTo(anchorID) }
                        return .handled
                    }
                    .onKeyPress(.space) {
                        onQuickLook(selectedEntries.compactMap { coordinator.fullImageURL(for: $0) })
                        return .handled
                    }
                    // The Mac backspace key sends U+007F, not `.delete` (U+0008).
                    .onKeyPress(keys: [.delete, .deleteForward, KeyEquivalent("\u{7F}")]) { _ in
                        guard !selection.isEmpty else { return .ignored }
                        confirmDelete(selectedEntries)
                        return .handled
                    }
                }
            }

            // Status bar
            Divider()
            statusBar
        }
        .onAppear { coordinator.loadEntries() }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                filterButton("All", filter: .all, count: coordinator.entryCount(for: .all))
                filterButton("Screenshots", filter: .screenshots, count: coordinator.entryCount(for: .screenshots))
                filterButton("Recordings", filter: .recordings, count: coordinator.entryCount(for: .recordings))
            }
            .padding(2)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button {
                coordinator.clearAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Clear History")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func filterButton(_ title: LocalizedStringKey, filter: HistoryFilter, count: Int) -> some View {
        Button {
            coordinator.setFilter(filter)
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(coordinator.currentFilter == filter ? .secondary : .tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(coordinator.currentFilter == filter ? .white.opacity(0.1) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .foregroundStyle(coordinator.currentFilter == filter ? .primary : .secondary)
    }

    // MARK: - Section

    private func sectionView(title: String, count: Int, entries: [HistoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)

                Text("\(count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                if entries.contains(where: { [.area, .fullscreen, .window].contains($0.captureMode) }) {
                    Button {
                        coordinator.exportAsPDF(entries)
                    } label: {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Export Screenshots as PDF")
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 165), spacing: 12)],
                spacing: 12
            ) {
                ForEach(entries) { entry in
                    HistoryItemView(entry: entry, coordinator: coordinator, isSelected: selection.contains(entry.id))
                        .id(entry.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            select(entry.id, modifiers: NSEvent.modifierFlags)
                        })
                }
            }
        }
    }

    // MARK: - Selection

    private var selectedEntries: [HistoryEntry] {
        coordinator.entries.filter { selection.contains($0.id) }
    }

    private func updateColumns(_ width: CGFloat) {
        // Matches the adaptive grid: 165pt minimum items with 12pt spacing.
        columns = max(1, Int((width - 32 + 12) / (165 + 12)))
    }

    private func select(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        isGridFocused = true
        let ids = coordinator.entries.map(\.id)
        if modifiers.contains(.command) {
            if selection.remove(id) == nil { selection.insert(id) }
            anchorID = id
        } else if modifiers.contains(.shift), let anchorID,
                  let from = ids.firstIndex(of: anchorID), let to = ids.firstIndex(of: id) {
            selection = Set(ids[min(from, to)...max(from, to)])
        } else {
            selection = [id]
            anchorID = id
        }
    }

    // ponytail: up/down step through the flat list by one row's worth of items, so
    // a row that ends a date section may land a few items off. Track per-section
    // positions if that turns out to matter.
    private func moveSelection(_ key: KeyEquivalent, extending: Bool) {
        let ids = coordinator.entries.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = anchorID.flatMap(ids.firstIndex(of:)) else {
            selection = [ids[0]]
            anchorID = ids[0]
            return
        }
        let step: Int
        switch key {
        case .leftArrow: step = -1
        case .rightArrow: step = 1
        case .upArrow: step = -columns
        default: step = columns
        }
        let next = ids[min(max(current + step, 0), ids.count - 1)]
        if extending {
            selection.insert(next)
        } else {
            selection = [next]
        }
        anchorID = next
    }

    private func confirmDelete(_ entries: [HistoryEntry]) {
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = entries.count == 1
            ? String(localized: "Delete capture?")
            : String(localized: "Delete \(entries.count) captures?")
        alert.informativeText = String(localized: "This will remove the capture from this Mac.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let cloudBox = entries.contains { $0.cloudURL != nil }
            ? NSButton(checkboxWithTitle: String(localized: "Also delete from cloud"), target: nil, action: nil)
            : nil
        cloudBox?.state = .on
        alert.accessoryView = cloudBox
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let alsoDeleteCloud = cloudBox?.state == .on
        let ids = coordinator.entries.map(\.id)
        let nextID = ids.firstIndex { selection.contains($0) }
            .flatMap { first in ids.dropFirst(first).first { !selection.contains($0) } }
        selection = nextID.map { [$0] } ?? []
        anchorID = nextID
        Task {
            for entry in entries {
                if alsoDeleteCloud, entry.cloudURL != nil {
                    await coordinator.deleteCloudCopy(for: entry)
                }
                coordinator.deleteEntry(entry)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("No captures yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Your screenshots and recordings will appear here")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text("\(coordinator.entries.count) items")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Circle()
                .fill(.tertiary)
                .frame(width: 2.5, height: 2.5)

            Text(formattedSize(coordinator.totalSize))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            Spacer()

            let retention = HistoryRetention(rawValue: coordinator.settings.historyRetention) ?? .oneMonth
            Text("Keeping \(retention.label.lowercased())")
                .font(.system(size: 11))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
    }

    private func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
