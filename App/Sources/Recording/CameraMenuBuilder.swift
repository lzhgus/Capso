// App/Sources/Recording/CameraMenuBuilder.swift
import AppKit
import AVFoundation
import SharedKit

@MainActor
final class CameraMenuBuilder: NSObject, NSMenuDelegate {
    let settings: AppSettings

    var onCameraSelected: ((String?) -> Void)?  // nil = None
    var onShapeSelected: ((CameraShape) -> Void)?
    var onSizeSelected: ((SharedKit.CameraSize) -> Void)?
    var onMirrorToggled: ((Bool) -> Void)?
    var onMenuClosed: (() -> Void)?

    /// The currently selected camera unique ID (nil = None).
    var selectedCameraID: String?

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        // CAMERA section
        addSectionHeader(menu, title: String(localized: "Camera"))
        let noneItem = makeItem(
            title: String(localized: "None"),
            isSelected: selectedCameraID == nil,
            action: #selector(selectNone)
        )
        menu.addItem(noneItem)

        for device in cameraDevices() {
            let item = makeItem(
                title: device.localizedName,
                isSelected: selectedCameraID == device.uniqueID,
                action: #selector(selectCamera(_:))
            )
            item.representedObject = device.uniqueID
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // SHAPE section
        addSectionHeader(menu, title: String(localized: "Shape"))
        for shape in CameraShape.allCases {
            let item = makeItem(
                title: shape.displayName,
                isSelected: settings.cameraShape == shape,
                action: #selector(selectShape(_:))
            )
            item.image = NSImage(systemSymbolName: shape.iconName, accessibilityDescription: shape.displayName)
            item.representedObject = shape.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // SIZE section
        addSectionHeader(menu, title: String(localized: "Size"))
        for size in SharedKit.CameraSize.allCases {
            let isCustom = settings.cameraCustomSizePt > 0
            let item = makeItem(
                title: size.displayName,
                isSelected: !isCustom && settings.cameraSize == size,
                action: #selector(selectSize(_:))
            )
            item.representedObject = size.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // OPTIONS section
        let mirrorItem = makeItem(
            title: String(localized: "Mirror"),
            isSelected: settings.cameraMirror,
            action: #selector(toggleMirror)
        )
        menu.addItem(mirrorItem)

        // Wire all items to this builder so selectors fire on it
        for item in menu.items where item.action != nil {
            item.target = self
        }

        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        onMenuClosed?()
    }

    private func addSectionHeader(_ menu: NSMenu, title: String) {
        let header = NSMenuItem(title: title.uppercased(), action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
    }

    private func makeItem(title: String, isSelected: Bool, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.state = isSelected ? .on : .off
        return item
    }

    private func cameraDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    // MARK: - Actions

    @objc private func selectNone() {
        onCameraSelected?(nil)
    }

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        onCameraSelected?(id)
    }

    @objc private func selectShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shape = CameraShape(rawValue: raw) else { return }
        settings.cameraShape = shape
        onShapeSelected?(shape)
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let size = SharedKit.CameraSize(rawValue: raw) else { return }
        settings.cameraSize = size
        settings.cameraCustomSizePt = 0  // selecting a preset clears custom size
        onSizeSelected?(size)
    }

    @objc private func toggleMirror() {
        settings.cameraMirror.toggle()
        onMirrorToggled?(settings.cameraMirror)
    }
}

// MARK: - Display helpers

private extension CameraShape {
    var displayName: String {
        switch self {
        case .circle: return String(localized: "Circle")
        case .square: return String(localized: "Square")
        case .landscape: return String(localized: "Landscape (16:9)")
        case .portrait: return String(localized: "Portrait (9:16)")
        }
    }

    var iconName: String {
        switch self {
        case .circle: return "circle"
        case .square: return "square"
        case .landscape: return "rectangle"
        case .portrait: return "rectangle.portrait"
        }
    }
}

private extension SharedKit.CameraSize {
    var displayName: String {
        switch self {
        case .small: return String(localized: "Small")
        case .medium: return String(localized: "Medium")
        case .large: return String(localized: "Large")
        }
    }
}
