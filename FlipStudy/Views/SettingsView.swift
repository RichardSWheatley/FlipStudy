import SwiftUI
import SwiftData

/// App settings. The one gated control is Cloud AI: because FlipStudy is aimed
/// at kids, turning it on requires a grown-up to pass a simple math check first.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var showingParentGate = false
    /// What to do once the grown-up gate is passed — enabling Cloud AI, or
    /// selecting a specific cloud engine.
    @State private var pendingUnlock: (() -> Void)?
    @State private var apiKey = ""
    /// When true the API key is shown as plain text so a grown-up can verify the
    /// exact characters. A masked SecureField hides paste corruption (truncation,
    /// autofill hijacking), which looks identical to a wrong key — so we let the
    /// key be revealed and checked.
    @State private var revealKey = false
    @State private var region = ""
    @State private var isTesting = false
    /// Result of the last "Test connection" tap: success text or a parsed error.
    @State private var testResult: TestResult?

    private enum TestResult {
        case success(String)
        case failure(String)
    }

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use a Cloud Translator", isOn: cloudBinding)
                } header: {
                    Text("Translation")
                } footer: {
                    Text("Cards are always drafted on your device — free and private. This only changes the engine used to translate language decks: leave it off for Apple's on-device translator, or turn it on to use Google or Microsoft with your own API key. A grown-up has to turn this on.")
                }

                Section {
                    Picker("Engine", selection: providerBinding) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    if selectedProvider.isCloud {
                        HStack {
                            // A plain TextField when revealed avoids the strong-
                            // password / autofill overlay that can silently mangle
                            // a pasted key in a SecureField.
                            Group {
                                if revealKey {
                                    TextField("API key", text: $apiKey)
                                } else {
                                    SecureField("API key", text: $apiKey)
                                }
                            }
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.none)
                            .font(.body.monospaced())
                            .onChange(of: apiKey) { _, newValue in
                                CloudTranslationKey.save(newValue, for: selectedProvider)
                            }
                            Button {
                                revealKey.toggle()
                            } label: {
                                Image(systemName: revealKey ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(revealKey ? "Hide API key" : "Show API key")
                        }
                        if revealKey, !apiKey.isEmpty {
                            Text("^[\(apiKey.count) character](inflect: true)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if selectedProvider == .microsoft {
                            TextField("Region (e.g. eastus)", text: $region)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onChange(of: region) { _, newValue in
                                    settings?.cloudTranslationRegion =
                                        newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                        }
                        Button {
                            Task { await testConnection() }
                        } label: {
                            if isTesting {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Testing…")
                                }
                            } else {
                                Label("Test Connection", systemImage: "checkmark.seal")
                            }
                        }
                        .disabled(isTesting || apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let testResult {
                            switch testResult {
                            case .success(let text):
                                Label(text, systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            case .failure(let text):
                                Label(text, systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } header: {
                    Text("Translation Engine")
                } footer: {
                    Text(microsoftFootnote)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingParentGate) {
                ParentGateView {
                    pendingUnlock?()
                    pendingUnlock = nil
                }
            }
            .onAppear {
                ensureSettings()
                // Move a pre-1.2 single shared key onto the engine that's set,
                // then load that engine's own key.
                CloudTranslationKey.migrateLegacyKey(to: selectedProvider)
                apiKey = CloudTranslationKey.read(for: selectedProvider)
                region = settings?.cloudTranslationRegion ?? ""
            }
            .onChange(of: selectedProvider) { _, newProvider in
                // Each engine has its own key slot — swap the field to the newly
                // selected engine's key so a Microsoft key can never be shown or
                // sent under Google (or vice versa).
                apiKey = CloudTranslationKey.read(for: newProvider)
                revealKey = false
                testResult = nil
            }
        }
    }

    private var selectedProvider: TranslationProvider {
        settings?.translationProvider ?? .apple
    }

    /// The engine footnote, with an extra line for Microsoft explaining that a
    /// region is required — the missing region is the usual cause of a 401.
    private var microsoftFootnote: String {
        if selectedProvider == .microsoft {
            return selectedProvider.footnote
                + " Microsoft also needs the Region from your Translator resource's \"Keys and Endpoint\" page (e.g. eastus), or it returns a 401."
        }
        return selectedProvider.footnote
    }

    /// Fire a tiny English → Italian translation with the entered key/region and
    /// report the parsed result, so key setup can be verified without leaving
    /// Settings. Uses the same `CloudTranslator` the app uses, so a success here
    /// means Generate Cards will work too.
    private func testConnection() async {
        isTesting = true
        testResult = nil
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let results = try await CloudTranslator(provider: selectedProvider, apiKey: key,
                                                    source: .english, target: .italian,
                                                    region: trimmedRegion)
                .translate(["Hello"])
            let translated = results.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if translated.isEmpty {
                testResult = .failure("Connected, but no translation came back. Check the key's resource type.")
            } else {
                testResult = .success("Works! \"Hello\" → \"\(translated)\"")
            }
        } catch {
            testResult = .failure(error.localizedDescription)
        }
        isTesting = false
    }

    /// Selecting a cloud engine requires Cloud AI to be on. If it isn't, picking
    /// a cloud engine opens the grown-up gate, which both enables Cloud AI and
    /// sets the engine once passed.
    private var providerBinding: Binding<TranslationProvider> {
        Binding(
            get: { selectedProvider },
            set: { newValue in
                guard let settings else { return }
                if newValue.isCloud && !settings.cloudAIEnabled {
                    pendingUnlock = {
                        settings.cloudAIEnabled = true
                        settings.translationProvider = newValue
                    }
                    showingParentGate = true
                } else {
                    settings.translationProvider = newValue
                }
            }
        )
    }

    /// Reflects the stored flag, but flipping it ON only opens the parent gate —
    /// the flag itself is set once the grown-up passes the check.
    private var cloudBinding: Binding<Bool> {
        Binding(
            get: { settings?.cloudAIEnabled ?? false },
            set: { newValue in
                if newValue {
                    pendingUnlock = { settings?.cloudAIEnabled = true }
                    showingParentGate = true
                } else {
                    settings?.cloudAIEnabled = false
                    // Fall back to the free on-device engine when cloud is off.
                    settings?.translationProvider = .apple
                }
            }
        )
    }

    private func ensureSettings() {
        if settingsList.isEmpty {
            context.insert(AppSettings())
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// A lightweight "ask a grown-up" gate: solve a multiplication problem that's
/// beyond a young child. Not real security — just a speed bump before enabling
/// an online feature, matching common kids-app practice.
private struct ParentGateView: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void

    @State private var first = Int.random(in: 6...9)
    @State private var second = Int.random(in: 6...9)
    @State private var answer = ""
    @State private var showedWrong = false

    private var canConfirm: Bool {
        !answer.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("\(first) × \(second) =")
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                        TextField("Answer", text: $answer)
                            .keyboardType(.numberPad)
                    }
                    if showedWrong {
                        Text("That's not right. Try again.")
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Grown-Up Check")
                } footer: {
                    Text("Ask a grown-up to solve this to turn on a cloud translator.")
                }
            }
            .navigationTitle("Grown-Up Check")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { check() }
                        .disabled(!canConfirm)
                }
            }
        }
    }

    private func check() {
        if Int(answer.trimmingCharacters(in: .whitespaces)) == first * second {
            onSuccess()
            dismiss()
        } else {
            showedWrong = true
            answer = ""
            first = Int.random(in: 6...9)
            second = Int.random(in: 6...9)
        }
    }
}
