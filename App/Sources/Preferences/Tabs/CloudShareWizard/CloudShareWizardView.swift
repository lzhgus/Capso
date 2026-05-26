// App/Sources/Preferences/Tabs/CloudShareWizard/CloudShareWizardView.swift
import AppKit
import Observation
import SwiftUI
import SharedKit
import ShareKit

// MARK: - Wizard root

struct CloudShareWizardView: View {
    @Bindable var viewModel: PreferencesViewModel
    let onComplete: () -> Void

    @State private var model = CloudShareWizardModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(Color.white.opacity(0.08))

            ZStack {
                // Cross-fade between steps
                stepContent
                    .id(model.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().background(Color.white.opacity(0.08))
            footer
        }
        .frame(width: 640, height: 560)
        .background(
            ZStack {
                // Subtle gradient overlay on top of the sheet's vibrancy
                LinearGradient(
                    colors: [
                        Color(red: 0.10, green: 0.10, blue: 0.12),
                        Color(red: 0.06, green: 0.06, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(0.92)
            }
        )
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.18), value: model.step)
    }

    // MARK: Header (title bar surrogate)

    private var header: some View {
        HStack(spacing: 10) {
            Text(String(localized: "Cloud Share Setup"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
            Spacer()
            Button {
                onComplete()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help(String(localized: "Close"))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: Body content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                switch model.step {
                case .welcome:    WelcomeStep(model: model)
                case .provider:   ProviderStep(model: model)
                case .getKeys:    GetKeysStep(model: model)
                case .credentials: CredentialsStep(model: model)
                case .urlPrefix:  URLPrefixStep(model: model)
                case .done:       DoneStep(model: model, onComplete: onComplete)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Footer (progress + actions)

    private var footer: some View {
        HStack(spacing: 14) {
            ProgressDots(current: model.step.rawValue, total: CloudShareWizardModel.WizardStep.allCases.count)
            Text("\(model.step.rawValue + 1) of \(CloudShareWizardModel.WizardStep.allCases.count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .monospacedDigit()
            Spacer()

            if model.step != .welcome && model.step != .done {
                Button(String(localized: "Back")) {
                    model.goBack()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                // No .cancelAction here — the close (X) button owns Escape.
                // Two cancelAction shortcuts in the same scene have undefined behavior.
            }

            primaryActionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        switch model.step {
        case .welcome, .provider, .getKeys, .credentials:
            WizardPrimaryButton(
                title: String(localized: "Next"),
                isEnabled: model.canAdvance
            ) {
                model.goNext()
            }
        case .urlPrefix:
            if case .success = model.testState {
                WizardPrimaryButton(
                    title: String(localized: "Save"),
                    isEnabled: true
                ) {
                    Task { await save() }
                }
            } else {
                WizardPrimaryButton(
                    title: String(localized: "Next"),
                    isEnabled: false  // disabled until test succeeds
                ) {}
                .opacity(0.5)
            }
        case .done:
            WizardPrimaryButton(
                title: String(localized: "Done"),
                isEnabled: true
            ) {
                onComplete()
            }
        }
    }

    private func save() async {
        // Step 1: Keychain first — if this fails, abort (no AppSettings writes,
        // so the UI never shows a half-saved "configured" state).
        let keychain = KeychainHelper(service: "com.awesomemacapps.capso.share.\(model.provider.rawValue)")
        do {
            try keychain.set(model.accessKey, account: "accessKey")
            try keychain.set(model.secretKey, account: "secretKey")
        } catch {
            // Surface the failure on the URL-prefix step's test panel — the user
            // sees the error and stays on screen 5 with their data intact.
            model.testState = .failure(.unknown(String(format: String(localized: "Could not save credentials to Keychain: %@"), error.localizedDescription)))
            return
        }

        // Step 2: Persist non-secret values via the viewModel so its
        // @Observable mutations fire (this is what drives the
        // notConfiguredView → configuredView transition in CloudShareSettingsView).
        viewModel.cloudShareProvider = model.provider.rawValue
        viewModel.cloudShareURLPrefix = ShareConfig.normalizePrefix(model.urlPrefix)
        viewModel.cloudShareAccountID = model.provider == .r2 ? model.accountID : nil
        viewModel.cloudShareRegion = model.provider == .r2 ? nil : model.region
        viewModel.cloudShareEndpoint = model.endpoint.isEmpty ? nil : model.endpoint
        viewModel.cloudSharePathPrefix = model.pathPrefix.isEmpty ? nil : model.pathPrefix
        viewModel.cloudShareBucket = model.bucket

        // Step 3: Rebuild the live ShareCoordinator with the new credentials.
        // Use AppDelegate.shared (NSApp.delegate cast fails under SwiftUI adaptor).
        AppDelegate.shared?.refreshShareCoordinator()

        // Step 4: Advance to the success screen.
        model.advanceTo(.done)
    }
}

// MARK: - View model

@MainActor
@Observable
final class CloudShareWizardModel {
    var step: WizardStep = .welcome

    // Form state
    var provider: ShareProvider = .r2
    var accountID: String = ""
    var region: String = ""
    var endpoint: String = ""
    var pathPrefix: String = ""
    var bucket: String = ""
    var accessKey: String = ""
    var secretKey: String = ""
    var urlPrefix: String = ""

    // Field-blur tracking for inline validation (only show errors after the user
    // has interacted with — and left — a field).
    var blurredAccountID: Bool = false
    var blurredBucket: Bool = false
    var blurredAccessKey: Bool = false

    // Reveal toggle for the secret-access-key field
    var showSecret: Bool = false

    // Test-connection state machine
    var testState: TestState = .idle

    enum WizardStep: Int, CaseIterable {
        case welcome = 0
        case provider
        case getKeys
        case credentials
        case urlPrefix
        case done
    }

    enum TestState: Equatable {
        case idle
        case validating(phase: String)
        case success(roundTripSeconds: TimeInterval)
        case failure(ShareError)
    }

    // MARK: Navigation

    var canAdvance: Bool {
        switch step {
        case .welcome:     return true
        case .provider:    return true
        case .getKeys:     return true
        case .credentials: return credentialsValid
        case .urlPrefix:
            if case .success = testState { return true }
            return false
        case .done:        return true
        }
    }

    var credentialsValid: Bool {
        providerSpecificFieldsValid
            && accountIDError == nil
            && bucketError == nil
            && accessKeyError == nil
            && !bucket.isEmpty
            && !accessKey.isEmpty
            && !secretKey.isEmpty
    }

    var providerSpecificFieldsValid: Bool {
        switch provider {
        case .r2:
            return !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .s3, .tencentCOS, .aliyunOSS:
            return !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var providerDisplayName: String {
        provider.displayName
    }

    var regionLabel: String {
        switch provider {
        case .r2:
            return String(localized: "Account ID")
        case .s3:
            return String(localized: "Region")
        case .tencentCOS:
            return String(localized: "Region")
        case .aliyunOSS:
            return String(localized: "Endpoint / Region")
        }
    }

    var regionPlaceholder: String {
        switch provider {
        case .r2:
            return String(localized: "32-character hex")
        case .s3:
            return "us-east-1"
        case .tencentCOS:
            return "ap-guangzhou"
        case .aliyunOSS:
            return "oss-cn-hangzhou"
        }
    }

    var accessKeyLabel: String {
        switch provider {
        case .tencentCOS:
            return "SecretId"
        case .aliyunOSS:
            return String(localized: "AccessKey ID")
        case .r2, .s3:
            return String(localized: "Access Key ID")
        }
    }

    var secretKeyLabel: String {
        switch provider {
        case .aliyunOSS:
            return String(localized: "AccessKey Secret")
        case .r2, .s3, .tencentCOS:
            return String(localized: "Secret Access Key")
        }
    }

    var endpointPlaceholder: String {
        switch provider {
        case .s3:
            return String(localized: "Optional for S3-compatible services")
        case .r2, .tencentCOS, .aliyunOSS:
            return ""
        }
    }

    var shouldShowEndpoint: Bool {
        provider == .s3
    }

    var configFields: [String: String] {
        var fields: [String: String] = [:]
        if !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["accountID"] = accountID
        }
        if !region.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["region"] = region
        }
        if !endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["endpoint"] = endpoint
        }
        if !pathPrefix.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            fields["pathPrefix"] = pathPrefix
        }
        return fields
    }

    func goNext() {
        guard let next = WizardStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    func goBack() {
        guard let prev = WizardStep(rawValue: step.rawValue - 1) else { return }
        // Clear test state when leaving the URL-prefix step backwards
        if step == .urlPrefix { testState = .idle }
        step = prev
    }

    func advanceTo(_ s: WizardStep) {
        step = s
    }

    // MARK: Inline validation

    /// Returns nil if the value passes the heuristic, or a localized error message.
    var accountIDError: String? {
        guard blurredAccountID, !accountID.isEmpty else { return nil }
        let trimmed = accountID.trimmingCharacters(in: .whitespaces)
        let hex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        let isAllHex = trimmed.unicodeScalars.allSatisfy { hex.contains($0) }
        if trimmed.count != 32 || !isAllHex {
            return String(localized: "Looks short — Cloudflare Account IDs are 32 hex characters")
        }
        return nil
    }

    var bucketError: String? {
        guard blurredBucket, !bucket.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let trimmed = bucket.trimmingCharacters(in: .whitespaces)
        if trimmed.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return String(localized: "Bucket names must be lowercase, no spaces")
        }
        return nil
    }

    var accessKeyError: String? {
        guard blurredAccessKey, !accessKey.isEmpty else { return nil }
        let trimmed = accessKey.trimmingCharacters(in: .whitespaces)
        if trimmed.count < 16 {
            return String(localized: "Cloudflare R2 Access Key IDs are typically 32+ chars. This looks like an API token instead — verify you created an R2 token, not a regular API token.")
        }
        return nil
    }

    var prefixError: String? {
        guard !urlPrefix.isEmpty else { return nil }
        do {
            try ShareConfig.validatePrefix(urlPrefix)
            return nil
        } catch let err as ShareError {
            if case .invalidURLPrefix(let reason) = err { return reason }
            return String(describing: err)
        } catch {
            return error.localizedDescription
        }
    }

    var canTest: Bool {
        guard !urlPrefix.isEmpty, prefixError == nil else { return false }
        if case .validating = testState { return false }
        return true
    }

    // MARK: Test execution

    func runConnectionTest() async {
        testState = .validating(phase: String(localized: "Uploading test file…"))

        // Phase narrator — runs concurrently to give the user confidence the test
        // isn't stuck. We cancel it explicitly once the real call returns so a
        // fast network round-trip isn't padded out to 1.4s by sleep tasks.
        let narrator = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if case .validating = self.testState {
                self.testState = .validating(phase: String(localized: "Fetching public URL…"))
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if case .validating = self.testState {
                self.testState = .validating(phase: String(localized: "Cleaning up…"))
            }
        }

        let result = await CloudShareTester.runTest(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: configFields,
            accessKey: accessKey,
            secretKey: secretKey
        )

        // Cancel the narrator BEFORE writing the final state. Any in-flight phase
        // update will see the still-`.validating` state when it checks, but its
        // own `Task.isCancelled` guard will keep it from writing.
        narrator.cancel()

        // If the outer test Task was cancelled (e.g. user edited the URL prefix
        // mid-flight), don't write a stale `.success`/`.failure` — `onChange`
        // already reset `testState` to `.idle`.
        guard !Task.isCancelled else { return }

        switch result {
        case .success(let dt): testState = .success(roundTripSeconds: dt)
        case .failure(let err): testState = .failure(err)
        }
    }
}

// MARK: - Step 1: Welcome

private struct WelcomeStep: View {
    @Bindable var model: CloudShareWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center, spacing: 14) {
                IconBadge(systemName: "icloud.and.arrow.up.fill",
                          gradient: [Color(red: 0.45, green: 0.30, blue: 0.95), Color(red: 0.30, green: 0.20, blue: 0.85)])
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "Set up Cloud Share"))
                        .font(.system(size: 24, weight: .bold))
                    Text(String(localized: "Step 1 — Introduction"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .textCase(.uppercase)
                        .tracking(0.8)
                }
                Spacer()
            }

            Text(.init(String(localized: "Capso uploads to **your own cloud storage** — never our servers. You bring the bucket, you own the files, you keep the bill. We just hand you the share link.")))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.78))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                CheckBullet(
                    title: String(localized: "Yours forever."),
                    detail: String(localized: "Files live in your account. Cancel Capso, keep your screenshots.")
                )
                CheckBullet(
                    title: String(localized: "Free tier friendly."),
                    detail: String(localized: "Cloudflare R2 includes 10 GB and zero egress fees.")
                )
                CheckBullet(
                    title: String(localized: "Five minutes to set up."),
                    detail: String(localized: "Paste four keys, test, done.")
                )
            }
            .padding(.top, 4)

            Spacer(minLength: 8)

            InfoCard(
                tint: Color(red: 0.30, green: 0.55, blue: 0.95),
                icon: "info.circle.fill",
                text: String(localized: "Already have credentials? You'll be done in under a minute.")
            )
        }
    }
}

// MARK: - Step 2: Provider

private struct ProviderStep: View {
    @Bindable var model: CloudShareWizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            StepHeader(
                stepLabel: String(localized: "Step 2 — Provider"),
                title: String(localized: "Choose a storage provider"),
                subtitle: String(localized: "Choose where Capso uploads screenshots. Files stay in your own storage account and Capso copies the public share link.")
            )

            VStack(spacing: 10) {
                ProviderCard(
                    badge: "R2",
                    badgeColor: Color(red: 0.96, green: 0.45, blue: 0.10),
                    name: String(localized: "Cloudflare R2"),
                    sub: String(localized: "10 GB free · $0 egress · S3-compatible"),
                    pillText: String(localized: "RECOMMENDED"),
                    pillColor: Color(red: 0.20, green: 0.78, blue: 0.40),
                    selected: model.provider == .r2,
                    enabled: true
                ) {
                    model.provider = .r2
                }
                ProviderCard(
                    badge: "S3",
                    badgeColor: Color(red: 0.62, green: 0.40, blue: 0.20),
                    name: String(localized: "Amazon S3"),
                    sub: String(localized: "AWS buckets and S3-compatible endpoints"),
                    pillText: nil,
                    pillColor: Color.white.opacity(0.20),
                    selected: model.provider == .s3,
                    enabled: true
                ) {
                    model.provider = .s3
                }
                ProviderCard(
                    badge: "COS",
                    badgeColor: Color(red: 0.25, green: 0.55, blue: 0.95),
                    name: String(localized: "Tencent COS"),
                    sub: String(localized: "Tencent Cloud object storage"),
                    pillText: nil,
                    pillColor: Color.white.opacity(0.20),
                    selected: model.provider == .tencentCOS,
                    enabled: true
                ) {
                    model.provider = .tencentCOS
                }
                ProviderCard(
                    badge: "OSS",
                    badgeColor: Color(red: 0.95, green: 0.36, blue: 0.18),
                    name: String(localized: "Aliyun OSS"),
                    sub: String(localized: "Alibaba Cloud object storage"),
                    pillText: nil,
                    pillColor: Color.white.opacity(0.20),
                    selected: model.provider == .aliyunOSS,
                    enabled: true
                ) {
                    model.provider = .aliyunOSS
                }
            }

            Spacer(minLength: 8)
        }
    }
}

// MARK: - Step 3: Get keys

private struct GetKeysStep: View {
    @Bindable var model: CloudShareWizardModel

    private var steps: [(title: String, detail: AttributedString)] {
        [
            (String(localized: "Create or choose a bucket"),
             Self.attributed(String(format: String(localized: "Use a bucket in **%@** that Capso can write objects into."), model.providerDisplayName))),
            (String(localized: "Make uploaded files publicly readable"),
             Self.attributed(String(localized: "Use a public bucket URL or connect a custom domain/CDN. Capso needs a public HTTPS prefix so it can copy a share link."))),
            (String(localized: "Create access credentials"),
             Self.attributed(String(localized: "Create a key with object read/write permission scoped to this bucket when your provider supports scoped keys."))),
            (String(localized: "Copy the required values"),
             Self.attributed(String(localized: "Keep the bucket, region/endpoint, access key, and secret ready. The secret will be stored in macOS Keychain.")))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                stepLabel: String(localized: "Step 3 — Provider"),
                title: String(format: String(localized: "Prepare %@ credentials"), model.providerDisplayName),
                subtitle: String(localized: "Open your provider dashboard and keep this window nearby. You'll paste the values on the next screen.")
            )

            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { idx, item in
                    if idx > 0 {
                        Divider().background(Color.white.opacity(0.08))
                    }
                    NumberedStepRow(number: idx + 1, title: item.title, detail: item.detail)
                }
            }
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            )

            HStack {
                Spacer()
                Button {
                    NSWorkspace.shared.open(providerURL)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(localized: "Open Provider Dashboard"))
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.30, green: 0.55, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 0.92)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var providerURL: URL {
        switch model.provider {
        case .r2:
            return URL(string: "https://dash.cloudflare.com/?to=/:account/r2/overview")!
        case .s3:
            return URL(string: "https://s3.console.aws.amazon.com/s3/home")!
        case .tencentCOS:
            return URL(string: "https://console.cloud.tencent.com/cos")!
        case .aliyunOSS:
            return URL(string: "https://oss.console.aliyun.com/")!
        }
    }

    /// Render `text` with backtick-delimited spans as monospace pills.
    /// Markdown-style **bold** is also recognized.
    private static func attributed(_ raw: String) -> AttributedString {
        // Use SwiftUI's Markdown to handle **bold** and `code`.
        if let parsed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            var result = parsed
            // Visually upgrade the inline code spans
            for run in result.runs where run.inlinePresentationIntent?.contains(.code) == true {
                let range = run.range
                result[range].font = .system(size: 12.5, weight: .medium, design: .monospaced)
                result[range].foregroundColor = Color(red: 0.85, green: 0.92, blue: 1.0)
                result[range].backgroundColor = Color.white.opacity(0.10)
            }
            return result
        }
        return AttributedString(raw)
    }
}

// MARK: - Step 4: Credentials

private struct CredentialsStep: View {
    @Bindable var model: CloudShareWizardModel

    @FocusState private var focused: Field?

    enum Field: Hashable {
        case accountID, region, endpoint, pathPrefix, bucket, accessKey, secretKey
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                stepLabel: String(localized: "Step 4 — Credentials"),
                title: String(localized: "Paste your credentials"),
                subtitle: String(localized: "These are stored in macOS Keychain on this Mac and never sent anywhere except your bucket.")
            )

            VStack(alignment: .leading, spacing: 14) {
                if model.provider == .r2 {
                    FieldGroup(
                        label: model.regionLabel,
                        icon: nil,
                        error: model.accountIDError
                    ) {
                        MonoTextField(
                            text: $model.accountID,
                            placeholder: model.regionPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .accountID)
                        .onChange(of: focused) { _, newValue in
                            if newValue != .accountID && !model.accountID.isEmpty {
                                model.blurredAccountID = true
                            }
                        }
                    }
                } else {
                    FieldGroup(
                        label: model.regionLabel,
                        icon: nil,
                        error: nil
                    ) {
                        MonoTextField(
                            text: $model.region,
                            placeholder: model.regionPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .region)
                    }
                }

                if model.shouldShowEndpoint {
                    FieldGroup(
                        label: String(localized: "Endpoint"),
                        icon: nil,
                        error: nil
                    ) {
                        MonoTextField(
                            text: $model.endpoint,
                            placeholder: model.endpointPlaceholder,
                            secure: false
                        )
                        .focused($focused, equals: .endpoint)
                    }
                }

                FieldGroup(
                    label: String(localized: "Bucket name"),
                    icon: nil,
                    error: model.bucketError
                ) {
                    MonoTextField(
                        text: $model.bucket,
                        placeholder: String(localized: "lowercase, hyphens OK"),
                        secure: false
                    )
                    .focused($focused, equals: .bucket)
                    .onChange(of: focused) { _, newValue in
                        if newValue != .bucket && !model.bucket.isEmpty {
                            model.blurredBucket = true
                        }
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    FieldGroup(
                        label: model.accessKeyLabel,
                        icon: nil,
                        error: model.accessKeyError
                    ) {
                        MonoTextField(
                            text: $model.accessKey,
                            placeholder: String(localized: "32+ characters"),
                            secure: false
                        )
                        .focused($focused, equals: .accessKey)
                        .onChange(of: focused) { _, newValue in
                            if newValue != .accessKey && !model.accessKey.isEmpty {
                                model.blurredAccessKey = true
                            }
                        }
                    }
                    FieldGroup(
                        label: model.secretKeyLabel,
                        icon: "lock.fill",
                        error: nil
                    ) {
                        SecretField(
                            text: $model.secretKey,
                            isRevealed: $model.showSecret,
                            placeholder: String(localized: "Won't be shown again")
                        )
                        .focused($focused, equals: .secretKey)
                    }
                }

                FieldGroup(
                    label: String(localized: "Path prefix"),
                    icon: nil,
                    error: nil
                ) {
                    MonoTextField(
                        text: $model.pathPrefix,
                        placeholder: String(localized: "Optional, e.g. screenshots"),
                        secure: false
                    )
                    .focused($focused, equals: .pathPrefix)
                }
            }

            Spacer(minLength: 8)

            // Trust footer
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(red: 0.40, green: 0.85, blue: 0.55))
                Text(String(localized: "Stored in Keychain · Encrypted at rest · Never leaves this device"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

// MARK: - Step 5: URL prefix + test

private struct URLPrefixStep: View {
    @Bindable var model: CloudShareWizardModel

    // Tracks the in-flight test so a prefix edit can cancel it. Without this,
    // a slow test can write a stale `.success(...)` for the previous prefix.
    @State private var currentTestTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StepHeader(
                stepLabel: String(localized: "Step 5 — Public URL"),
                title: String(localized: "Public URL & test"),
                subtitle: String(localized: "Capso uses this HTTPS prefix to build the share link after upload. Use your public bucket URL, custom domain, or CDN URL.")
            )

            FieldGroup(
                label: String(localized: "Public URL prefix"),
                icon: "link",
                error: model.prefixError
            ) {
                MonoTextField(
                    text: $model.urlPrefix,
                    placeholder: "https://cdn.example.com",
                    secure: false
                )
                .onChange(of: model.urlPrefix) { _, _ in
                    // Any prefix change invalidates the previous test result —
                    // including in-flight ones. Cancel the running task so the
                    // narrator and `runConnectionTest`'s `Task.isCancelled` guard
                    // both bail without writing a stale state.
                    if model.testState != .idle {
                        model.testState = .idle
                    }
                    currentTestTask?.cancel()
                    currentTestTask = nil
                }
            }

            // Live preview
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Final share link will look like"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(previewLink)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(model.urlPrefix.isEmpty ? 0.35 : 0.85))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Test result panel
            testResultPanel
                .frame(maxWidth: .infinity)

            Spacer(minLength: 4)
        }
    }

    private var previewLink: String {
        let prefix = model.urlPrefix.isEmpty ? "https://<your-prefix>" : ShareConfig.normalizePrefix(model.urlPrefix)
        let key = ShareConfig.normalizePathPrefix(model.pathPrefix) + "2026-04-25-screenshot.png"
        return "\(prefix)/\(key)"
    }

    /// Cancel any in-flight test before launching a new one, and store the new
    /// task handle so a subsequent prefix edit can cancel it.
    private func runTest() {
        currentTestTask?.cancel()
        currentTestTask = Task { await model.runConnectionTest() }
    }

    @ViewBuilder
    private var testResultPanel: some View {
        switch model.testState {
        case .idle:
            HStack {
                Spacer()
                TestButton(
                    label: String(localized: "Test Connection"),
                    icon: "bolt.fill",
                    enabled: model.canTest,
                    style: .primary
                ) {
                    runTest()
                }
            }

        case .validating(let phase):
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(phase)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .id(phase)
                    .transition(.opacity)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            )
            .animation(.easeInOut(duration: 0.2), value: phase)

        case .success(let dt):
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Color(red: 0.30, green: 0.85, blue: 0.50))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Connection works."))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(String(format: String(localized: "Round-trip in %.1fs · Test file written and removed cleanly."), dt))
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    TestButton(
                        label: String(localized: "Re-test"),
                        icon: "arrow.clockwise",
                        enabled: true,
                        style: .secondary
                    ) {
                        runTest()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 0.12, green: 0.30, blue: 0.18).opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.30, green: 0.85, blue: 0.50).opacity(0.40), lineWidth: 0.5)
            )

        case .failure(let err):
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(red: 0.95, green: 0.55, blue: 0.20))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(humanize(err).headline)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text(humanize(err).detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                HStack {
                    Spacer()
                    TestButton(
                        label: String(localized: "Re-test"),
                        icon: "arrow.clockwise",
                        enabled: true,
                        style: .secondary
                    ) {
                        runTest()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(red: 0.30, green: 0.15, blue: 0.10).opacity(0.50))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(red: 0.95, green: 0.55, blue: 0.20).opacity(0.40), lineWidth: 0.5)
            )
        }
    }

    private func humanize(_ err: ShareError) -> (headline: String, detail: String) {
        switch err {
        case .notConfigured:
            return (String(localized: "Configuration is incomplete."),
                    String(localized: "One or more required values are missing. Go back and double-check the previous step."))
        case .invalidCredentials:
            return (String(localized: "Those credentials were rejected."),
                    String(localized: "The storage provider returned an authentication error. Verify the access key, secret, and bucket permissions."))
        case .invalidURLPrefix(let reason):
            return (String(localized: "That URL prefix doesn't look right."),
                    reason)
        case .network(let underlying):
            return (String(localized: "Network error reaching storage."),
                    underlying)
        case .quotaExceeded:
            return (String(localized: "Storage quota exceeded."),
                    String(localized: "Your storage account is at its limit. Free up space or upgrade your provider plan."))
        case .publicAccessUnreachable:
            return (String(localized: "The upload worked, but the file isn't publicly reachable."),
                    String(localized: "The bucket URL is not publicly readable. Enable public access or use a public custom domain, then re-test."))
        case .unknown(let s):
            return (String(localized: "Something went wrong."),
                    s)
        }
    }
}

// MARK: - Step 6: Done

private struct DoneStep: View {
    @Bindable var model: CloudShareWizardModel
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.30, green: 0.85, blue: 0.50).opacity(0.30),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 80, weight: .regular))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.45, green: 0.95, blue: 0.60),
                                Color(red: 0.20, green: 0.78, blue: 0.42)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            Text(String(localized: "Cloud Share is ready"))
                .font(.system(size: 22, weight: .bold))

            Text(String(localized: "Next time you capture a screenshot, click the cloud icon in Quick Access — your share link will be on your clipboard, ready to paste in Slack or Discord."))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.70))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                onComplete()
                // Slight delay so the sheet closes first, then capture is invoked.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) {
                    AppDelegate.shared?.captureCoordinator?.captureArea()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                    Text(String(localized: "Take a test capture"))
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Shared helpers / components

private struct StepHeader: View {
    let stepLabel: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(stepLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .textCase(.uppercase)
                .tracking(0.8)
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.70))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct IconBadge: View {
    let systemName: String
    let gradient: [Color]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                .shadow(color: gradient.first?.opacity(0.35) ?? .clear, radius: 12, y: 5)
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct CheckBullet: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.20, green: 0.78, blue: 0.42).opacity(0.20))
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(red: 0.40, green: 0.95, blue: 0.55))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
    }
}

private struct InfoCard: View {
    let tint: Color
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(tint.opacity(0.95))
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.80))
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tint.opacity(0.30), lineWidth: 0.5)
        )
    }
}

private struct ProviderCard: View {
    let badge: String
    let badgeColor: Color
    let name: String
    let sub: String
    let pillText: String?
    let pillColor: Color
    let selected: Bool
    let enabled: Bool
    let onTap: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                // Square badge
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(badgeColor)
                        .frame(width: 44, height: 44)
                    Text(badge)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        if let pillText {
                            StatusPill(text: pillText, color: pillColor)
                        }
                    }
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(red: 0.30, green: 0.55, blue: 0.98))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(selected ? Color.white.opacity(0.06) : (hovered && enabled ? Color.white.opacity(0.05) : Color.white.opacity(0.03)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        selected
                            ? Color(red: 0.30, green: 0.55, blue: 0.98).opacity(0.85)
                            : Color.white.opacity(0.10),
                        lineWidth: selected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.50)
        .disabled(!enabled)
        .onHover { hovered = $0 && enabled }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white.opacity(0.95))
            .tracking(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(color.opacity(0.85))
            )
    }
}

private struct NumberedStepRow: View {
    let number: Int
    let title: String
    let detail: AttributedString

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Number badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.white.opacity(0.06)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 26, height: 26)
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .overlay(
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct FieldGroup<Content: View>: View {
    let label: String
    let icon: String?
    let error: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
            content
            if let error {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(red: 0.95, green: 0.50, blue: 0.45))
                        .padding(.top, 1)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.95, green: 0.65, blue: 0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct MonoTextField: View {
    @Binding var text: String
    let placeholder: String
    let secure: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: .regular, design: .monospaced))
        .foregroundStyle(.white.opacity(0.95))
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private struct SecretField: View {
    @Binding var text: String
    @Binding var isRevealed: Bool
    let placeholder: String

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if isRevealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .regular, design: .monospaced))
            .foregroundStyle(.white.opacity(0.95))
            .padding(.leading, 10)
            .padding(.vertical, 9)

            Button {
                isRevealed.toggle()
            } label: {
                Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isRevealed ? String(localized: "Hide secret") : String(localized: "Reveal secret"))
        }
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

private enum TestButtonStyle { case primary, secondary }

private struct TestButton: View {
    let label: String
    let icon: String
    let enabled: Bool
    let style: TestButtonStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1.0 : 0.4)
        .disabled(!enabled)
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: [Color(red: 0.30, green: 0.55, blue: 0.98), Color(red: 0.20, green: 0.45, blue: 0.92)],
                startPoint: .top, endPoint: .bottom
            )
        case .secondary:
            Color.white.opacity(0.10)
        }
    }
}

private struct WizardPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(minWidth: 86)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.55, blue: 0.98),
                            Color(red: 0.20, green: 0.45, blue: 0.92)
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1.0 : 0.4)
        .disabled(!isEnabled)
        .keyboardShortcut(.defaultAction)
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? Color(red: 0.30, green: 0.55, blue: 0.98) : Color.white.opacity(0.18))
                    .frame(width: i == current ? 8 : 6, height: i == current ? 8 : 6)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
                    .animation(.easeInOut(duration: 0.2), value: current)
            }
        }
    }
}

// MARK: - Test runner (shared between wizard step 5 and the configured-state Test button)

@MainActor
enum CloudShareTester {
    static func runTest(
        provider: ShareProvider,
        urlPrefix: String,
        bucket: String,
        fields: [String: String],
        accessKey: String,
        secretKey: String
    ) async -> Result<TimeInterval, ShareError> {
        // Validate the prefix on this side first so the user gets a sharper
        // error message instead of an opaque network failure.
        do {
            try ShareConfig.validatePrefix(urlPrefix)
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }

        let config = ShareConfig(
            provider: provider,
            urlPrefix: urlPrefix,
            bucket: bucket,
            fields: fields
        )
        let dest: any ShareDestination
        do {
            dest = try ShareDestinationFactory.make(config: config, accessKey: accessKey, secretKey: secretKey)
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }

        let start = Date()
        do {
            try await dest.validateConfig()
            return .success(Date().timeIntervalSince(start))
        } catch let err as ShareError {
            return .failure(err)
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
