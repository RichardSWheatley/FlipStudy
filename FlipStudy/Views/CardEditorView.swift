import SwiftUI
import SwiftData

struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let deck: Deck
    /// nil means we're creating a new card.
    let card: Card?

    @State private var front = ""
    @State private var back = ""

    private var isEditing: Bool { card != nil }
    private var canSave: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Front") {
                    TextField("Question or term", text: $front, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section("Back") {
                    TextField("Answer or definition", text: $back, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let card {
                    front = card.front
                    back = card.back
                }
            }
        }
    }

    private func save() {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card {
            card.front = f
            card.back = b
        } else {
            let newCard = Card(front: f, back: b)
            newCard.deck = deck
            context.insert(newCard)
        }
        dismiss()
    }
}
