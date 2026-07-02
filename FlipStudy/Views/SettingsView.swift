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

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use Cloud AI", isOn: cloudBinding)
                } header: {
                    Text("AI Card Generation")
                } footer: {
                    Text("On-device AI is always free and private. Cloud AI can make richer cards, but it sends the topic you type to an online service. A grown-up has to turn this on.")
                }

                Section {
                    Picker("Engine", selection: providerBinding) {
                        ForEach(TranslationProvider.allCases) { provider in
                            Text(provider.label).tag(provider)
                        }
                    }
                    if selectedProvider.isCloud {
                        SecureField("API key", text: $apiKey)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: apiKey) { _, newValue in
                                CloudTranslationKey.save(newValue)
                            }
                    }
                } header: {
                    Text("Translation Engine")
                } footer: {
                    Text(selectedProvider.footnote)
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
                apiKey = CloudTranslationKey.read()
            }
        }
    }

    private var selectedProvider: TranslationProvider {
        settings?.translationProvider ?? .apple
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
                    Text("Ask a grown-up to solve this to turn on Cloud AI.")
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
