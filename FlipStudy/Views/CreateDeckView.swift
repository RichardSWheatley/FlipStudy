import SwiftUI
import SwiftData

struct CreateDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var subject = ""

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title (e.g. Spanish Verbs)", text: $title)
                    TextField("Subject (optional)", text: $subject)
                } header: {
                    Text("Deck")
                } footer: {
                    Text("Add cards by hand once the deck is created. Making cards from a subject, a book, or a photo comes in later updates.")
                }
            }
            .navigationTitle("New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
    }

    private func create() {
        let deck = Deck(
            title: trimmedTitle,
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            source: .manual
        )
        context.insert(deck)
        dismiss()
    }
}

#Preview {
    CreateDeckView()
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self], inMemory: true)
}
