import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context

    @State private var editorCard: Card?
    @State private var showingNewCard = false
    /// The study screen open over the deck, in whichever mode was chosen.
    @State private var studyMode: StudyMode?
    @State private var showingEditDeck = false

    private var sortedCards: [Card] {
        deck.allCards.sorted { $0.leitnerBox != $1.leitnerBox ? $0.leitnerBox < $1.leitnerBox : $0.front < $1.front }
    }

    /// A temporary `.flipstudy` file for the share sheet. Rebuilt each time the
    /// menu is opened so it always reflects the deck's current cards.
    private var shareURL: URL? {
        try? DeckTransfer.exportFile(for: deck)
    }

    var body: some View {
        List {
            Section {
                // Tapping the banner is the quick way to change the deck's
                // colour and emoji (or its name).
                Button {
                    showingEditDeck = true
                } label: {
                    DeckBanner(deck: deck)
                }
                .buttonStyle(SquishButtonStyle())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityHint("Change the deck's name, color and emoji")
            }
            if deck.allCards.isEmpty {
                VStack(spacing: 10) {
                    Text("✏️")
                        .font(.system(size: 48))
                    Text("No cards yet")
                        .font(.headline)
                    Text("Tap + to add your first card.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                Section {
                    ForEach(sortedCards) { card in
                        Button {
                            editorCard = card
                        } label: {
                            CardRow(card: card, palette: deck.palette)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCards)
                } header: {
                    Text("Cards")
                }
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(deck.palette.bottom)
        .safeAreaInset(edge: .bottom) {
            if !deck.allCards.isEmpty {
                VStack(spacing: 10) {
                    Button {
                        studyMode = .flashcards
                    } label: {
                        Label("Study", systemImage: "play.fill")
                            .font(.title3.bold())
                    }
                    .buttonStyle(ChunkyButtonStyle(deck.palette.gradient))
                    HStack(spacing: 10) {
                        modeButton("Type It", systemImage: "keyboard", mode: .typeAnswer, palette: .ocean)
                        modeButton("Quiz", systemImage: "checklist", mode: .multipleChoice, palette: .grape)
                            .disabled(!QuizBuilder.canQuiz(backs: deck.allCards.map(\.back)))
                        modeButton("Match", systemImage: "square.grid.2x2", mode: .match, palette: .tangerine)
                            .disabled(!QuizBuilder.canMatch(matchPairs))
                    }
                }
                .padding()
                .background(.bar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewCard = true
                } label: {
                    Label("Add Card", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingEditDeck = true
                    } label: {
                        Label("Edit Deck", systemImage: "pencil")
                    }
                    if !deck.allCards.isEmpty, let shareURL {
                        ShareLink(item: shareURL) {
                            Label("Share Deck", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingNewCard) {
            CardEditorView(deck: deck, card: nil)
        }
        .sheet(isPresented: $showingEditDeck) {
            CreateDeckView(deck: deck)
        }
        .sheet(item: $editorCard) { card in
            CardEditorView(deck: deck, card: card)
        }
        .fullScreenCover(item: $studyMode) { mode in
            if mode == .match {
                MatchView(deck: deck)
            } else {
                StudyView(deck: deck, mode: mode)
            }
        }
    }

    private var matchPairs: [QuizBuilder.MatchPair] {
        deck.allCards.map { .init(id: $0.id, front: $0.front, back: $0.back) }
    }

    /// Quiz and Match need at least three different cards; they stay greyed
    /// out until the deck has them.
    private func modeButton(_ title: String, systemImage: String, mode: StudyMode, palette: DeckPalette) -> some View {
        ModeButton(title: title, systemImage: systemImage, palette: palette) {
            studyMode = mode
        }
    }

    private func deleteCards(_ offsets: IndexSet) {
        let targets = offsets.map { sortedCards[$0] }
        for card in targets {
            context.delete(card)
        }
    }
}

/// The deck's colour, emoji and size at the top of its card list.
private struct DeckBanner: View {
    let deck: Deck

    var body: some View {
        let count = deck.allCards.count
        HStack(spacing: 14) {
            Text(deck.displayEmoji)
                .font(.system(size: 52))
            VStack(alignment: .leading, spacing: 4) {
                Text(deck.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(deck.dueCount > 0
                     ? "^[\(count) card](inflect: true) · \(deck.dueCount) ready to study"
                     : "^[\(count) card](inflect: true)")
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
            }
            Spacer(minLength: 0)
            Image(systemName: "paintbrush.pointed.fill")
                .font(.subheadline)
                .padding(8)
                .background(.white.opacity(0.25), in: Circle())
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .padding(20)
        .background(deck.palette.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// A Type It / Quiz / Match button in its own bright colour.
private struct ModeButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let palette: DeckPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.bold))
            }
        }
        .buttonStyle(ChunkyButtonStyle(isEnabled ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.gray.opacity(0.35))))
    }
}

private struct CardRow: View {
    let card: Card
    let palette: DeckPalette

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.front)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            LevelDots(level: card.leitnerBox, palette: palette)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// How well a card is known, as five dots filling up — friendlier than
/// "Box 3" for a child.
private struct LevelDots: View {
    let level: Int
    let palette: DeckPalette

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...Card.maxBox, id: \.self) { dot in
                Circle()
                    .fill(dot <= level ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.gray.opacity(0.2)))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Level \(level) of \(Card.maxBox)")
    }
}
