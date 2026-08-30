// App/Sources/Preferences/Components/AutomationURLsSheetView.swift
import SwiftUI
import AppKit

struct AutomationCommandItem: Identifiable {
    let id: String
    let name: LocalizedStringKey
    let urlString: String
}

struct AutomationCommandSection: Identifiable {
    let id: String
    let title: LocalizedStringKey
    let items: [AutomationCommandItem]
}

struct AutomationURLsSheetView: View {
    @Binding var isPresented: Bool
    @State private var copiedURL: String? = nil
    @State private var copiedAll = false

    private let sections: [AutomationCommandSection] = [
        AutomationCommandSection(
            id: "screenshots",
            title: "Screenshots",
            items: [
                AutomationCommandItem(id: "all-in-one", name: "All-in-One", urlString: "capso://grab/all-in-one"),
                AutomationCommandItem(id: "area", name: "Capture Area", urlString: "capso://grab/area"),
                AutomationCommandItem(id: "fullscreen", name: "Capture Fullscreen", urlString: "capso://grab/fullscreen"),
                AutomationCommandItem(id: "window", name: "Capture Window", urlString: "capso://grab/window"),
                AutomationCommandItem(id: "scrolling", name: "Scrolling Capture", urlString: "capso://grab/scrolling"),
                AutomationCommandItem(id: "self-timer", name: "Self-Timer", urlString: "capso://grab/self-timer"),
                AutomationCommandItem(id: "last-area", name: "Capture Previous Area", urlString: "capso://grab/last-area"),
                AutomationCommandItem(id: "clipboard", name: "Capture Area to Clipboard", urlString: "capso://grab/clipboard"),
                AutomationCommandItem(id: "share", name: "Capture and Share to Cloud", urlString: "capso://grab/share"),
                AutomationCommandItem(id: "annotate", name: "Capture Area & Annotate", urlString: "capso://grab/annotate")
            ]
        ),
        AutomationCommandSection(
            id: "clipboard",
            title: "Clipboard",
            items: [
                AutomationCommandItem(id: "pin", name: "Pin from Clipboard", urlString: "capso://grab/pin"),
                AutomationCommandItem(id: "edit-clipboard", name: "Edit Clipboard Image", urlString: "capso://grab/edit-clipboard"),
                AutomationCommandItem(id: "open-image", name: "Open Image File", urlString: "capso://grab/open-image")
            ]
        ),
        AutomationCommandSection(
            id: "ocr-translation",
            title: "Text & Translation",
            items: [
                AutomationCommandItem(id: "ocr", name: "Capture Text (OCR)", urlString: "capso://grab/ocr"),
                AutomationCommandItem(id: "translate", name: "Capture & Translate", urlString: "capso://grab/translate"),
                AutomationCommandItem(id: "translate-selection", name: "Translate Selected Text", urlString: "capso://grab/translate-selection"),
                AutomationCommandItem(id: "translate-text", name: "Translate Typed Text", urlString: "capso://grab/translate-text")
            ]
        ),
        AutomationCommandSection(
            id: "recording",
            title: "Recording",
            items: [
                AutomationCommandItem(id: "record", name: "Record Area", urlString: "capso://grab/record"),
                AutomationCommandItem(id: "record-fullscreen", name: "Record Full Screen", urlString: "capso://grab/record-fullscreen")
            ]
        ),
        AutomationCommandSection(
            id: "app-history",
            title: "History & Settings",
            items: [
                AutomationCommandItem(id: "history", name: "Screenshot History", urlString: "capso://grab/history"),
                AutomationCommandItem(id: "preferences", name: "Preferences", urlString: "capso://grab/preferences")
            ]
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation URLs")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Trigger Capso actions from Raycast, Alfred, Shortcuts, or shell scripts.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(copiedAll ? "Copied All" : "Copy All") {
                    copyAllURLs()
                }
                .controlSize(.small)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .padding(.leading, 2)

                            SettingCard {
                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                    commandRow(item: item, showDivider: index > 0)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 360)

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.regular)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func commandRow(item: AutomationCommandItem, showDivider: Bool) -> some View {
        SettingRow(label: item.name, showDivider: showDivider) {
            Button {
                copyURL(item.urlString)
            } label: {
                HStack(spacing: 6) {
                    Text(item.urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(copiedURL == item.urlString ? Color.green : Color.secondary)

                    Image(systemName: copiedURL == item.urlString ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(copiedURL == item.urlString ? Color.green : Color.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color.primary.opacity(copiedURL == item.urlString ? 0.12 : 0.05),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .help("Click to copy URL")
        }
    }

    private func copyURL(_ urlString: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        copiedURL = urlString
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedURL == urlString {
                copiedURL = nil
            }
        }
    }

    private func copyAllURLs() {
        var lines: [String] = []
        for section in sections {
            for item in section.items {
                lines.append(item.urlString)
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        copiedAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedAll = false
        }
    }
}
