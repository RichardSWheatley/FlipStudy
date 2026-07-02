import SwiftUI
import SwiftData

/// App settings. The one gated control is Cloud AI: because FlipStudy is aimed
/// at kids, turning it on requires a grown-up to pass a simple math check first.
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var showingParentGate = false

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
                    settings?.cloudAIEnabled = true
                }
            }
            .onAppear(perform: ensureSettings)
        }
    }

    /// Reflects the stored flag, but flipping it ON only opens the parent gate —
    /// the flag itself is set once the grown-up passes the check.
    private var cloudBinding: Binding<Bool> {
        Binding(
            get: { settings?.cloudAIEnabled ?? false },
            set: { newValue in
                if newValue {
                    showingParentGate = true
                } else {
                    settings?.cloudAIEnabled = false
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
