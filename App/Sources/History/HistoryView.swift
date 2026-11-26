// App/Sources/History/HistoryView.swift
import SwiftUI
import UniformTypeIdentifiers
import HistoryKit

struct HistoryView: View {
    let coordinator: HistoryCoordinator
    var onQuickLook: ([URL]) -> Void = { _ in }

    @State private var selection: Set<UUID> = []
    @State private var anchorID: UUID?
    @State private var columns = 1
    @State private var isDropTargeted = false
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
                formatter.dateFormat = "EEEE"
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

    private var showsCollectionsSection: Bool {
        switch coordinator.currentFilter {
        case .all:
            !coordinator.collections.isEmpty
        case .collections:
            true
        case .screenshots, .recordings:
            false
        }
    }

    private var isContentEmpty: Bool {
        switch coordinator.currentFilter {
        case .collections:
            coordinator.collections.isEmpty
        case .all:
            coordinator.entries.isEmpty && coordinator.collections.isEmpty
        case .screenshots, .recordings:
            coordinator.entries.isEmpty
        }
    }

    private var selectedScreenshots: [HistoryEntry] {
        selectedEntries.filter { [.area, .fullscreen, .window, .pdfPage].contains($0.captureMode) }
    }

    var body: some View {
        Group {
            if let activeCollection = coordinator.activeCollection {
                HistoryCollectionDetailView(
                    collection: activeCollection,
                    coordinator: coordinator,
                    onQuickLook: onQuickLook
                )
            } else {
                mainBrowserView
            }
        }
        .onAppear { coordinator.loadEntries() }
    }

    private var mainBrowserView: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()

            if let progress = coordinator.pdfImportProgress {
                pdfImportProgressBanner(progress)
                Divider()
            }

            if let error = coordinator.pdfImportError {
                pdfImportErrorBanner(error)
                Divider()
            }

            if isContentEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if showsCollectionsSection, !coordinator.collections.isEmpty {
                                collectionsSection
                            }

                            if coordinator.currentFilter != .collections {
                                ForEach(groupedEntries, id: \.0) { section, entries in
                                    sectionView(title: section, count: entries.count, entries: entries)
                                }
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

            Divider()
            statusBar
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Color.accentColor.opacity(0.08))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handlePDFDrop)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 1) {
                filterButton("All", filter: .all, count: coordinator.entryCount(for: .all))
                filterButton("Screenshots", filter: .screenshots, count: coordinator.entryCount(for: .screenshots))
                filterButton("Recordings", filter: .recordings, count: coordinator.entryCount(for: .recordings))
                filterButton("PDFs", filter: .collections, count: coordinator.entryCount(for: .collections))
            }
            .padding(2)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            if !selectedScreenshots.isEmpty {
                Button {
                    coordinator.exportAsPDF(selectedScreenshots)
                } label: {
                    Label(
                        String(localized: "Export PDF (\(selectedScreenshots.count))"),
                        systemImage: "doc.richtext"
                    )
                    .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export Selected Screenshots as PDF")
            }

            Button {
                coordinator.importPDFWithPanel()
            } label: {
                Label(String(localized: "Import PDF"), systemImage: "doc.badge.plus")
                    .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Import a PDF file into Screenshot History")

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

    // MARK: - PDF Import Banners

    private func pdfImportProgressBanner(_ progress: HistoryCoordinator.PDFImportProgress) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: progress.fraction)
                .frame(width: 120)
            Text("Importing \(progress.fileName) (\(progress.completedPages)/\(progress.totalPages))…")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button("Cancel") {
                coordinator.cancelPDFImport()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11.5, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.25))
    }

    private func pdfImportErrorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                coordinator.dismissPDFImportError()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.orange.opacity(0.1))
    }

    // MARK: - Collections Section

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("PDF Collections")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Rectangle()
                    .fill(.quaternary)
                    .frame(height: 0.5)

                Text("\(coordinator.collections.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 165), spacing: 12)],
                spacing: 12
            ) {
                ForEach(coordinator.collections) { summary in
                    HistoryCollectionCard(
                        summary: summary,
                        coordinator: coordinator
                    )
                }
            }
        }
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
                    let collectionTargets: [HistoryEntry] = selection.contains(entry.id) && selectedScreenshots.count > 1
                        ? selectedScreenshots
                        : [entry]
                    HistoryItemView(
                        entry: entry,
                        coordinator: coordinator,
                        isSelected: selection.contains(entry.id),
                        entriesForCollectionAction: collectionTargets
                    )
                    .id(entry.id)
                    .simultaneousGesture(TapGesture().onEnded {
                        select(entry.id, modifiers: NSEvent.modifierFlags)
                    })
                }
            }
        }
    }

    // MARK: - Drop Handling

    private func handlePDFDrop(providers: [NSItemProvider]) -> Bool {
        let matching = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !matching.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in matching {
                if let url = await Self.loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            let pdfs = urls.filter { $0.pathExtension.lowercased() == "pdf" }
            if !pdfs.isEmpty {
                coordinator.importPDFFiles(pdfs)
            }
        }
        return true
    }

    static func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Selection

    private var selectedEntries: [HistoryEntry] {
        coordinator.entries.filter { selection.contains($0.id) }
    }

    private func updateColumns(_ width: CGFloat) {
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
            if coordinator.currentFilter == .collections {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
                Text("No PDF collections yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Import or drop a PDF to annotate pages, interleave screenshots, and export back to PDF")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Import PDF…") {
                    coordinator.importPDFWithPanel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(.top, 6)
            } else {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 28))
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 4)
                Text("No captures yet")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Your screenshots, recordings, and imported PDFs will appear here")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 6) {
            let itemCount = coordinator.currentFilter == .collections
                ? coordinator.collections.count
                : coordinator.entries.count + (coordinator.currentFilter == .all ? coordinator.collections.count : 0)
            Text("\(itemCount) items")
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

// MARK: - PDF Collection Card

private struct HistoryCollectionCard: View {
    let summary: HistoryCollectionSummary
    let coordinator: HistoryCoordinator

    @State private var isHovered = false
    @State private var coverImage: NSImage?
    @State private var showRenameSheet = false
    @State private var renameDraft = ""

    private var timeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: summary.collection.updatedAt, relativeTo: Date())
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white.opacity(0.05))
                        .offset(x: 3, y: -3)
                        .scaleEffect(0.96)

                    coverView
                        .frame(maxWidth: .infinity)
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // PDF Deck badge
                HStack(spacing: 3) {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 8.5, weight: .semibold))
                    Text("\(summary.pageCount)")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.88))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(6)

                if isHovered {
                    HStack(spacing: 5) {
                        cardActionButton("folder", help: String(localized: "Open PDF Collection")) {
                            coordinator.openCollection(summary.id)
                        }
                        cardActionButton("square.and.arrow.up", help: String(localized: "Export PDF")) {
                            coordinator.exportCollectionAsPDF(summary.collection)
                        }
                        cardActionButton("trash", help: String(localized: "Delete Collection")) {
                            confirmDeleteCollection()
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.collection.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 4) {
                    Text(timeString)
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 2, height: 2)
                    Text("\(summary.pageCount) pages")
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
        }
        .background(.white.opacity(isHovered ? 0.07 : 0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(isHovered ? 0.14 : 0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(isHovered ? 0.22 : 0), radius: 8, y: 2)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .onTapGesture {
            coordinator.openCollection(summary.id)
        }
        .onAppear { loadCover() }
        .onChange(of: summary.coverEntry?.id) { _, _ in loadCover() }
        .onChange(of: summary.coverEntry?.fileSize) { _, _ in loadCover() }
        .contextMenu {
            Button("Open") { coordinator.openCollection(summary.id) }
            Button("Export PDF…") { coordinator.exportCollectionAsPDF(summary.collection) }
            Button("Rename…") {
                renameDraft = summary.collection.title
                showRenameSheet = true
            }
            Divider()
            Button("Delete Collection", role: .destructive) {
                confirmDeleteCollection()
            }
        }
        .sheet(isPresented: $showRenameSheet) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Rename PDF Collection")
                    .font(.system(size: 14, weight: .semibold))
                TextField("Collection Title", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Spacer()
                    Button("Cancel") { showRenameSheet = false }
                    Button("Save") {
                        coordinator.renameCollection(summary.id, to: renameDraft)
                        showRenameSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(renameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
            .frame(width: 300)
        }
    }

    @ViewBuilder
    private var coverView: some View {
        if let coverImage {
            Image(nsImage: coverImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Rectangle()
                .fill(.quaternary.opacity(0.3))
                .overlay {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: 22))
                        .foregroundStyle(.quaternary)
                }
        }
    }

    private func cardActionButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func loadCover() {
        guard let cover = summary.coverEntry,
              let url = coordinator.thumbnailURL(for: cover) else {
            coverImage = nil
            return
        }
        coverImage = NSImage(contentsOf: url)
    }

    private func confirmDeleteCollection() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Delete PDF collection \"\(summary.collection.title)\"?")
        alert.informativeText = String(localized: "Imported PDF pages will be removed. Regular screenshots from your history will be kept.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        coordinator.deleteCollection(summary.id)
    }
}
