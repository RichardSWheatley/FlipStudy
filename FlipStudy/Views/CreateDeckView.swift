import SwiftUI
import SwiftData

struct CreateDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means we're creating a new deck; otherwise we're editing this one.
    var deck: Deck? = nil

    @State private var title = ""
    @State private var subject = ""

    private var isEditing: Bool { deck != nil }

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
                    if !isEditing {
                        Text("Add cards by hand once the deck is created. Making cards from a subject, a book, or a photo comes in later updates.")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Deck" : "New Deck")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
            .onAppear {
                if let deck {
                    title = deck.title
                    subject = deck.subject
                }
            }
        }
    }

    private func save() {
        let cleanTitle = trimmedTitle
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if let deck {
            deck.title = cleanTitle
            deck.subject = cleanSubject
        } else {
            let newDeck = Deck(title: cleanTitle, subject: cleanSubject, source: .manual)
            context.insert(newDeck)
        }
        dismiss()
    }
}

#Preview {
    CreateDeckView()
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self], inMemory: true)
}
