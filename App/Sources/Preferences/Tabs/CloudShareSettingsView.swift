// App/Sources/Preferences/Tabs/CloudShareSettingsView.swift
import SwiftUI
import SharedKit
import ShareKit

struct CloudShareSettingsView: View {
    @Bindable var viewModel: PreferencesViewModel
    @State private var showWizard = false
    @State private var testing = false
    @State private var testResult: TestResultAlert?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Cloud Share")
                .font(.system(size: 20, weight: .bold))

            if viewModel.isCloudShareConfigured {
                configuredView
            } else {
                notConfiguredView
            }
        }
        .sheet(isPresented: $showWizard) {
            CloudShareWizardView(viewModel: viewModel, onComplete: {
                showWizard = false
            })
        }
        .alert(item: $testResult) { result in
            Alert(
                title: Text(result.title),
                message: Text(result.message),
                dismissButton: .default(Text(String(localized: "OK")))
            )
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "icloud")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "Cloud Share is not set up yet"))
                .font(.headline)
            Text(String(localized: "Configure a Cloudflare R2 bucket to share captures with one click."))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(String(localized: "Set up Cloud Share")) {
                showWizard = true
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var configuredView: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingGroup(title: "Status") {
                SettingCard {
                    SettingRow(label: "Provider") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                            Text(viewModel.cloudShareProvider ?? "—")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    SettingRow(label: "Public URL Prefix", showDivider: true) {
                        Text(viewModel.cloudShareURLPrefix ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    SettingRow(label: "Bucket", showDivider: true) {
                        Text(viewModel.cloudShareBucket ?? "—")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SettingGroup(title: "Actions") {
                SettingCard {
                    SettingRow(label: "Test Connection", sublabel: "Verify the bucket is reachable") {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            HStack(spacing: 4) {
                                if testing {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.7)
                                }
                                Text(testing ? String(localized: "Testing…") : String(localized: "Test"))
                            }
                        }
                        .controlSize(.small)
                        .disabled(testing)
                    }
                    SettingRow(label: "Reset Configuration", sublabel: "Remove all Cloud Share credentials", showDivider: true) {
                        Button(String(localized: "Reset"), role: .destructive) {
                            resetConfig()
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    private func testConnection() async {
        guard
            let providerRaw = viewModel.cloudShareProvider,
            let provider = ShareProvider(rawValue: providerRaw),
            let urlPrefix = viewModel.cloudShareURLPrefix,
            let accountID = viewModel.cloudShareAccountID,
            let bucket = viewModel.cloudShareBucket
        else {
            testResult = TestResultAlert(
                title: String(localized: "Not configured"),
                message: String(localized: "Cloud Share isn't fully set up yet — re-run the wizard.")
            )
            return
        }

        let keychain = KeychainHelper(service: "com.awesomemacapps.capso.share.\(provider.rawValue)")
        let accessKey = (try? keychain.get(account: "accessKey")) ?? ""
        let secretKey = (try? keychain.get(account: "secretKey")) ?? ""

        guard !accessKey.isEmpty, !secretKey.isEmpty else {
            testResult = TestResultAlert(
                title: String(localized: "Credentials missing"),
                message: String(localized: "Couldn't read the Access Key or Secret Access Key from Keychain. Re-run the wizard to re-enter them.")
            )
            return
        }

        testing = true
        let result = await CloudShareTester.runTest(
            provider: provider,
            urlPrefix: urlPrefix,
            accountID: accountID,
            bucket: bucket,
            accessKey: accessKey,
            secretKey: secretKey
        )
        testing = false

        switch result {
        case .success(let dt):
            testResult = TestResultAlert(
                title: String(localized: "Connection works"),
                message: String(format: String(localized: "Round-trip in %.1fs · Test file uploaded and removed cleanly."), dt)
            )
        case .failure(let err):
            testResult = TestResultAlert(
                title: String(localized: "Test failed"),
                message: humanize(err)
            )
        }
    }

    private func humanize(_ err: ShareError) -> String {
        switch err {
        case .notConfigured:
            return String(localized: "Configuration is incomplete. Re-run the wizard.")
        case .invalidCredentials:
            return String(localized: "Cloudflare rejected the credentials. Verify the Access Key and Secret have Object Read & Write on this bucket.")
        case .invalidURLPrefix(let reason):
            return String(format: String(localized: "Invalid public URL prefix: %@"), reason)
        case .network(let underlying):
            return String(format: String(localized: "Network error: %@"), underlying)
        case .quotaExceeded:
            return String(localized: "Storage quota exceeded — free up space in the Cloudflare dashboard.")
        case .publicAccessUnreachable:
            return String(localized: "Upload worked, but the file isn't publicly reachable. Enable Public access on the bucket in Cloudflare.")
        case .unknown(let s):
            return s
        }
    }

    private func resetConfig() {
        // 1. Clear AppSettings (4 keys via viewModel for proper @Observable mutations)
        viewModel.cloudShareProvider = nil
        viewModel.cloudShareURLPrefix = nil
        viewModel.cloudShareAccountID = nil
        viewModel.cloudShareBucket = nil

        // 2. Delete Keychain entries — surface failures instead of silently swallowing.
        // r2 is the only provider in v1; when B2/S3 land, derive this string from cloudShareProvider.
        let keychain = KeychainHelper(service: "com.awesomemacapps.capso.share.r2")
        var keychainErrors: [String] = []
        do {
            try keychain.delete(account: "accessKey")
        } catch {
            keychainErrors.append("Access Key (\(error.localizedDescription))")
        }
        do {
            try keychain.delete(account: "secretKey")
        } catch {
            keychainErrors.append("Secret Access Key (\(error.localizedDescription))")
        }

        // 3. Tear down the live coordinator so subsequent shares fail closed.
        // Use AppDelegate.shared (NSApp.delegate cast fails under SwiftUI adaptor).
        let appDelegate = AppDelegate.shared
        appDelegate?.refreshShareCoordinator()

        // 4. Force the History UI to re-render so the upload button on each row
        //    re-evaluates `coordinator.shareCoordinator != nil` (now false).
        appDelegate?.historyCoordinator?.loadEntries()

        // 5. Sanity check (debug builds only). After all the above, the live
        //    ShareCoordinator MUST be nil; if not, refresh didn't propagate.
        #if DEBUG
        assert(appDelegate?.shareCoordinator == nil,
               "ShareCoordinator should be nil after reset")
        assert(appDelegate?.historyCoordinator?.shareCoordinator == nil,
               "HistoryCoordinator.shareCoordinator should be nil after reset")
        #endif

        // 6. If Keychain delete failed for either entry, alert the user.
        if !keychainErrors.isEmpty {
            let list = keychainErrors.joined(separator: ", ")
            testResult = TestResultAlert(
                title: String(localized: "Couldn't fully clear Keychain"),
                message: String(format: String(localized: "Some credentials may still be in Keychain: %@.\n\nOpen 'Keychain Access.app' and search for 'com.awesomemacapps.capso.share' to remove them manually."), list)
            )
        }
    }
}

// Alert wrapper — `Identifiable` lets `.alert(item:)` re-trigger when a new
// result lands (binding-by-Bool would skip the second presentation if the
// user cancels then re-tests too quickly).
struct TestResultAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
