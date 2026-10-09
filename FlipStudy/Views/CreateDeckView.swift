import SwiftUI
import SwiftData

struct CreateDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    /// nil means we're creating a new deck; otherwise we're editing this one.
    var deck: Deck? = nil

    @State private var title = ""
    @State private var subject = ""
    @State private var colorIndex = DeckPalette.allCases.randomElement()?.rawValue ?? 0
    /// Empty until an emoji is tapped; until then the title suggests one.
    @State private var emoji = ""

    private var palette: DeckPalette { DeckPalette(rawValue: colorIndex) ?? .ocean }
    private var shownEmoji: String {
        emoji.isEmpty ? DeckEmoji.automatic(title: title, subject: subject, seed: title) : emoji
    }

    private var isEditing: Bool { deck != nil }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    preview
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Title (e.g. Spanish Verbs)", text: $title)
                    TextField("Subject (optional)", text: $subject)
                } header: {
                    Text("Deck")
                } footer: {
                    if !isEditing {
                        Text("Add cards by hand once the deck is created.")
                    }
                }

                Section("Color") {
                    HStack(spacing: 0) {
                        ForEach(DeckPalette.allCases) { choice in
                            Button {
                                withAnimation(.spring(response: 0.3)) { colorIndex = choice.rawValue }
                            } label: {
                                Circle()
                                    .fill(choice.gradient)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if choice == palette {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.heavy))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    .scaleEffect(choice == palette ? 1.15 : 1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.name)
                            .accessibilityAddTraits(choice == palette ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Emoji") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(DeckEmoji.choices, id: \.self) { choice in
                            Button {
                                emoji = choice
                            } label: {
                                Text(choice)
                                    .font(.system(size: 30))
                                    .frame(width: 48, height: 48)
                                    .background(choice == shownEmoji ? palette.top.opacity(0.3) : Color.clear,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
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
                    colorIndex = deck.palette.rawValue
                    emoji = deck.displayEmoji
                }
            }
        }
    }

    /// What the deck will look like on the home screen.
    private var preview: some View {
        HStack(spacing: 14) {
            Text(shownEmoji)
                .font(.system(size: 48))
            Text(trimmedTitle.isEmpty ? "My New Deck" : trimmedTitle)
                .font(.title2.bold())
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .padding(20)
        .background(palette.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: palette.bottom.opacity(0.3), radius: 8, y: 4)
    }

    private func save() {
        let cleanTitle = trimmedTitle
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        // Keep the emoji that was showing, so it doesn't change if the
        // title is edited later.
        let chosenEmoji = shownEmoji
        if let deck {
            deck.title = cleanTitle
            deck.subject = cleanSubject
            deck.colorIndex = colorIndex
            deck.emoji = chosenEmoji
        } else {
            let newDeck = Deck(title: cleanTitle, subject: cleanSubject, source: .manual)
            newDeck.colorIndex = colorIndex
            newDeck.emoji = chosenEmoji
            context.insert(newDeck)
        }
        dismiss()
    }
}

#Preview {
    CreateDeckView()
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self, StudyDay.self], inMemory: true)
}
