import SwiftUI

/// "Explain This Card": FlipStudy Cloud says why the answer is right and gives
/// a trick for remembering it. Offered only while the cloud engine is in use,
/// since it sends the card's text to the Worker.
struct ExplainCardView: View {
    @Environment(\.dismiss) private var dismiss
    let front: String
    let back: String
    let subject: String
    /// Explanations already fetched this session, so asking about the same
    /// card twice doesn't spend the code's daily allowance again.
    @Binding var cache: [String: CardExplanation]

    @State private var result: CardExplanation?
    @State private var errorMessage: String?

    private var cacheKey: String { "\(subject)\n\(front)\n\(back)" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(front)
                            .font(.headline)
                        Text(back)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let result {
                        Text(result.explanation)
                        if !result.tip.isEmpty {
                            Label {
                                Text(result.tip)
                            } icon: {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        Text("Written by FlipStudy Cloud's AI, which can make mistakes.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("Couldn't Explain", systemImage: "exclamationmark.bubble")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again") { Task { await load() } }
                        }
                    } else {
                        ProgressView("Asking FlipStudy Cloud…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    }
                }
                .padding()
            }
            .navigationTitle("Explain This Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
        .presentationDetents([.medium, .large])
    }

    private func load() async {
        if let cached = cache[cacheKey] {
            result = cached
            return
        }
        errorMessage = nil
        do {
            let explanation = try await CloudCardGenerator.explain(front: front, back: back, subject: subject)
            cache[cacheKey] = explanation
            result = explanation
        } catch let error as CloudCardError {
            errorMessage = error.explanationMessage
        } catch {
            errorMessage = CloudCardError.network(error.localizedDescription).explanationMessage
        }
    }
}
