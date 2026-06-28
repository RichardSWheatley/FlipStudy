import SwiftUI
import SwiftData

struct DeckDetailView: View {
    @Bindable var deck: Deck
    @Environment(\.modelContext) private var context

    @State private var editorCard: Card?
    @State private var showingNewCard = false
    @State private var showingStudy = false
    @State private var showingEditDeck = false

    private var sortedCards: [Card] {
        deck.cards.sorted { $0.leitnerBox != $1.leitnerBox ? $0.leitnerBox < $1.leitnerBox : $0.front < $1.front }
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
                Button {
                    showingStudy = true
                } label: {
                    Label("Study", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
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
        .fullScreenCover(isPresented: $showingStudy) {
            StudyView(deck: deck)
        }
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
