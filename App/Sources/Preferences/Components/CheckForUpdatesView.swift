// App/Sources/Preferences/Components/CheckForUpdatesView.swift
import AppKit
import SwiftUI
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    enum StatusKind {
        case checking
        case success
        case error
    }

    struct Status {
        let message: String
        let kind: StatusKind
    }

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var status: Status?
    @Published var automaticallyDownloadsUpdates: Bool = false {
        didSet {
            guard oldValue != automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    private enum ManualCheckState {
        case none
        case probing
    }

    private var manualCheckState: ManualCheckState = .none
    private var probeFoundValidUpdate = false
    private var canCheckObservation: NSKeyValueObservation?
    private var autoDownloadObservation: NSKeyValueObservation?
    private var clearStatusTask: Task<Void, Never>?

    lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    var updater: SPUUpdater { updaterController.updater }

    override init() {
        super.init()
        automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
        canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
        autoDownloadObservation = updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates
            }
        }
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        clearStatusTask?.cancel()
        manualCheckState = .probing
        probeFoundValidUpdate = false
        status = Status(message: String(localized: "Checking…"), kind: .checking)
        updater.checkForUpdateInformation()
    }

    private func showStatus(_ message: String, kind: StatusKind, autoDismissAfter: Duration? = .seconds(4)) {
        clearStatusTask?.cancel()
        status = Status(message: message, kind: kind)

        guard let autoDismissAfter else { return }
        clearStatusTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: autoDismissAfter)
            guard !Task.isCancelled else { return }
            self?.status = nil
        }
    }

    private func clearManualProbeState() {
        manualCheckState = .none
        probeFoundValidUpdate = false
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        guard manualCheckState == .probing else { return }
        probeFoundValidUpdate = true
        status = nil
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        guard manualCheckState == .probing else { return }
        let message = error.localizedDescription.isEmpty ? String(localized: "You’re up to date!") : error.localizedDescription
        showStatus(message, kind: .success)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        guard manualCheckState == .probing else { return }
        let nsError = error as NSError
        guard !(nsError.domain == SUSparkleErrorDomain && nsError.code == 1001) else { return }
        showStatus(error.localizedDescription, kind: .error, autoDismissAfter: .seconds(6))
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        guard manualCheckState == .probing, updateCheck == .updateInformation else { return }

        let shouldLaunchInteractiveFlow = probeFoundValidUpdate && error == nil
        clearManualProbeState()

        if shouldLaunchInteractiveFlow {
            status = nil
            updater.checkForUpdates()
        }
    }
}

/// A SwiftUI wrapper around Capso's update manager that keeps manual
/// no-update feedback non-modal so the app remains capturable.
struct CheckForUpdatesView: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Button("Check for Updates") {
                updateManager.checkForUpdates()
            }
            .disabled(!updateManager.canCheckForUpdates)
            .controlSize(.small)

            if let status = updateManager.status {
                HStack(spacing: 6) {
                    switch status.kind {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }

                    Text(status.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: 220, alignment: .trailing)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: updateManager.status?.message)
    }
}
