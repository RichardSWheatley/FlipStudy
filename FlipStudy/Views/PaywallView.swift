import SwiftUI

/// The FlipStudy Pro paywall. Explains what the one-time purchase unlocks (the
/// on-device Apple Intelligence features) and lets a grown-up buy or restore it.
/// The purchase itself is handled entirely by Apple's system sheet — this view
/// only kicks it off and reacts to the result.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ProStore.self) private var proStore

    @State private var isWorking = false

    /// Called after Pro is successfully unlocked, so the presenter can continue
    /// straight into the feature the user wanted.
    var onUnlock: (() -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    featureList
                    purchaseArea
                    finePrint
                }
                .padding(24)
            }
            .navigationTitle("FlipStudy Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: proStore.isPro) { _, isPro in
                if isPro { finish() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
            Text("Unlock on-device AI")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("A one-time purchase that turns on FlipStudy's Apple Intelligence features — all still running privately on your device.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 18) {
            FeatureRow(icon: "text.book.closed",
                       title: "Type a Subject",
                       detail: "Type any topic and the AI drafts a full set of study cards for you.")
            FeatureRow(icon: "doc.viewfinder",
                       title: "Smart page scanning",
                       detail: "Scanning a page reads the text into real question-and-answer cards, not just line-by-line splits.")
            FeatureRow(icon: "lock.shield",
                       title: "Private by design",
                       detail: "Everything is generated on your device. No accounts, no servers, nothing to leak.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var purchaseArea: some View {
        VStack(spacing: 12) {
            Button {
                Task { await buy() }
            } label: {
                Group {
                    if isWorking {
                        ProgressView()
                    } else {
                        Text("Unlock Pro — \(proStore.priceText)")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking)

            Button("Restore Purchase") {
                Task { await restore() }
            }
            .font(.subheadline)
            .disabled(isWorking)

            if let error = proStore.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var finePrint: some View {
        Text("One-time purchase, not a subscription. Ask a grown-up before buying. Requires a device that supports Apple Intelligence.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    // MARK: - Actions

    private func buy() async {
        isWorking = true
        let ok = await proStore.purchase()
        isWorking = false
        if ok { finish() }
    }

    private func restore() async {
        isWorking = true
        await proStore.restore()
        isWorking = false
        if proStore.isPro { finish() }
    }

    private func finish() {
        onUnlock?()
        dismiss()
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
