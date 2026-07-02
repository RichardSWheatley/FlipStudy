import SwiftUI
import SwiftData

/// Create a deck by typing a topic and letting the on-device AI draft the cards.
/// The result is a preview the user reviews before the deck is actually made —
/// AI never silently creates content a child studies.
struct TypeSubjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var topic = ""
    @State private var title = ""
    @State private var draftCards: [(front: String, back: String)] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var hasGenerated = false

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedTopic.isEmpty && !isGenerating
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !draftCards.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Topic (e.g. French food vocabulary)", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Making cards…")
                            }
                        } else {
                            Label("Generate Cards", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canGenerate)
                } header: {
                    Text("Topic")
                } footer: {
                    Text("Cards are made on your device — free and private. Review them below before you create the deck.")
                }

                if let unavailable = AICardGenerator.unavailableReason {
                    Section {
                        Label(unavailable, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !draftCards.isEmpty {
                    Section("Deck") {
                        TextField("Deck title", text: $title)
                    }

                    Section("Preview (\(draftCards.count))") {
                        ForEach(Array(draftCards.enumerated()), id: \.offset) { _, card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.front)
                                    .font(.body.weight(.medium))
                                if !card.back.isEmpty {
                                    Text(card.back)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if hasGenerated && !isGenerating && errorMessage == nil {
                    Section {
                        Text("No cards yet. Try rewording the topic.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Type a Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
        }
    }

    private func generate() {
        errorMessage = nil
        isGenerating = true
        let requestedTopic = trimmedTopic
        Task {
            do {
                let cards = try await AICardGenerator.makeCards(topic: requestedTopic)
                draftCards = cards
                if trimmedTitle.isEmpty {
                    title = requestedTopic
                }
            } catch {
                draftCards = []
                errorMessage = error.localizedDescription
            }
            hasGenerated = true
            isGenerating = false
        }
    }

    private func create() {
        let deck = Deck(title: trimmedTitle,
                        subject: trimmedTopic,
                        source: .typedSubject)
        context.insert(deck)
        for draft in draftCards {
            let card = Card(front: draft.front, back: draft.back)
            card.deck = deck
            context.insert(card)
        }
        dismiss()
    }
}
