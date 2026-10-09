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
        deck.cards.sorted { $0.leitnerBox != $1.leitnerBox ? $0.leitnerBox < $1.leitnerBox : $0.front < $1.front }
    }

    /// A temporary `.flipstudy` file for the share sheet. Rebuilt each time the
    /// menu is opened so it always reflects the deck's current cards.
    private var shareURL: URL? {
        try? DeckTransfer.exportFile(for: deck)
    }

    var body: some View {
        List {
            if deck.cards.isEmpty {
                ContentUnavailableView {
                    Label("No Cards", systemImage: "rectangle.stack.badge.plus")
                } description: {
                    Text("Tap the + button to add your first card.")
                }
            } else {
                Section {
                    ForEach(sortedCards) { card in
                        Button {
                            editorCard = card
                        } label: {
                            CardRow(card: card)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteCards)
                }
            }
        }
        .navigationTitle(deck.title)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !deck.cards.isEmpty {
                VStack(spacing: 10) {
                    Button {
                        studyMode = .flashcards
                    } label: {
                        Label("Study", systemImage: "play.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    HStack(spacing: 10) {
                        modeButton("Type It", systemImage: "keyboard", mode: .typeAnswer)
                        modeButton("Quiz", systemImage: "checklist", mode: .multipleChoice)
                            .disabled(!QuizBuilder.canQuiz(backs: deck.cards.map(\.back)))
                        modeButton("Match", systemImage: "square.grid.2x2", mode: .match)
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
                    if !deck.cards.isEmpty, let shareURL {
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
        deck.cards.map { .init(id: $0.id, front: $0.front, back: $0.back) }
    }

    /// Quiz and Match need at least three different cards; they stay greyed
    /// out until the deck has them.
    private func modeButton(_ title: String, systemImage: String, mode: StudyMode) -> some View {
        Button {
            studyMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func deleteCards(_ offsets: IndexSet) {
        let targets = offsets.map { sortedCards[$0] }
        for card in targets {
            context.delete(card)
        }
    }
}

private struct CardRow: View {
    let card: Card

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.front)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            BoxBadge(box: card.leitnerBox)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

private struct BoxBadge: View {
    let box: Int

    var body: some View {
        Text("Box \(box)")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
