import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @State private var showingNewDeck = false
    @State private var showingPhotoDeck = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if decks.isEmpty {
                    ContentUnavailableView {
                        Label("No Decks Yet", systemImage: "rectangle.on.rectangle.angled")
                    } description: {
                        Text("Make your first deck and add some cards to start studying.")
                    } actions: {
                        Menu {
                            newDeckMenuItems
                        } label: {
                            Label("New Deck", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(decks) { deck in
                            NavigationLink(value: deck) {
                                DeckRow(deck: deck)
                            }
                        }
                        .onDelete(perform: deleteDecks)
                    }
                }
            }
            .navigationTitle("FlipStudy")
            .navigationDestination(for: Deck.self) { deck in
                DeckDetailView(deck: deck)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        newDeckMenuItems
                    } label: {
                        Label("New Deck", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewDeck) {
                CreateDeckView()
            }
            .sheet(isPresented: $showingPhotoDeck) {
                PhotoDeckView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    @ViewBuilder
    private var newDeckMenuItems: some View {
        Button {
            showingPhotoDeck = true
        } label: {
            Label("Scan a Page", systemImage: "doc.viewfinder")
        }
        Button {
            showingNewDeck = true
        } label: {
            Label("Blank Deck", systemImage: "square.and.pencil")
        }
    }

    private func deleteDecks(_ offsets: IndexSet) {
        for index in offsets {
            context.delete(decks[index])
        }
    }
}

private struct DeckRow: View {
    let deck: Deck

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deck.source.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(deck.title)
                    .font(.headline)
                let count = deck.cards.count
                Text("^[\(count) card](inflect: true)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if deck.dueCount > 0 {
                Text("\(deck.dueCount) due")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self], inMemory: true)
}
