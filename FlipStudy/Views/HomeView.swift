import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var proStore
    @Environment(FamilyLinkRouter.self) private var linkRouter
    @Query(sort: \Deck.createdAt, order: .reverse) private var decks: [Deck]
    @Query private var settingsList: [AppSettings]
    @Query private var studyDays: [StudyDay]
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingNewDeck = false
    @State private var showingPhotoDeck = false
    @State private var showingSubjectDeck = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    /// Which AI feature the user was heading into when the paywall appeared,
    /// so a successful unlock continues into that screen, not a fixed one.
    private enum PaywallDestination { case typeSubject, scanPage }
    @State private var paywallDestination: PaywallDestination = .typeSubject

    // Adding a shared deck: pick a `.flipstudy` file, preview it, then confirm.
    @State private var showingImporter = false
    @State private var pendingImport: SharedDeck?
    @State private var importError: String?

    private var settings: AppSettings? { settingsList.first }

    private var streak: Int {
        StudyProgress.currentStreak(studyDays: studyDays.filter { $0.reviewCount > 0 }.map(\.day))
    }

    private var reviewedToday: Int { StudyProgress.reviewed(on: .now, in: studyDays) }

    private var dailyGoal: Int { settings?.dailyGoal ?? AppSettings.defaultDailyGoal }

    /// Whether this user may open the smart features at all. The $0.99 purchase
    /// is one way in; a redeemed family code is the other, and family members
    /// shouldn't have to buy what they were already given.
    private var hasSmartAccess: Bool {
        proStore.isPro || CardEngine.cloudUnlocked(settings)
    }

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
                        Section {
                            ProgressHeader(streak: streak, reviewed: reviewedToday, goal: dailyGoal)
                        }
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
            // Keep the widget and the daily reminder in step with what's due.
            // Leaving the screen is the moment that matters: that's when the
            // widget is visible and the next reminder needs to be right.
            .task { StudyProgress.refresh(context: context, settings: settings) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { StudyProgress.refresh(context: context, settings: settings) }
            }
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
            .sheet(isPresented: $showingSubjectDeck) {
                TypeSubjectView()
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            // A join link was tapped: Settings is where the code is redeemed,
            // behind the grown-up check. `initial` covers a cold launch, where
            // the code is already waiting before this view appears.
            .onChange(of: linkRouter.pendingCode, initial: true) { _, code in
                if code != nil { showingSettings = true }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView {
                    // Unlocked: continue into the AI deck screen they wanted.
                    switch paywallDestination {
                    case .typeSubject: showingSubjectDeck = true
                    case .scanPage: showingPhotoDeck = true
                    }
                }
                .environment(proStore)
            }
            .fileImporter(isPresented: $showingImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .sheet(item: importSheetItem) { wrapper in
                ImportDeckSheet(deck: wrapper.deck) {
                    DeckTransfer.insert(wrapper.deck, into: context)
                    pendingImport = nil
                } onCancel: {
                    pendingImport = nil
                }
            }
            .alert("Couldn't Add Deck",
                   isPresented: Binding(get: { importError != nil },
                                        set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
    }

    /// `.sheet(item:)` needs an `Identifiable`; wrap the pending snapshot.
    private var importSheetItem: Binding<PendingDeck?> {
        Binding(
            get: { pendingImport.map(PendingDeck.init) },
            set: { if $0 == nil { pendingImport = nil } }
        )
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            pendingImport = try DeckTransfer.decode(contentsOf: url)
        } catch let error as DeckTransfer.TransferError {
            importError = error.errorDescription
        } catch {
            importError = "That file isn't a FlipStudy deck."
        }
    }

    @ViewBuilder
    private var newDeckMenuItems: some View {
        // The smart features — "Type a Subject" and "Scan a Page" — need an AI
        // that can actually run. Hide them on hardware that can never run Apple
        // Intelligence (e.g. a base iPhone 15) so we don't offer buttons that
        // always fail — unless a family code is redeemed, which brings its own
        // engine and makes them work on any iPhone. Both are Pro features:
        // users with neither Pro nor a code get the paywall, and buying it
        // drops them straight into the screen they wanted.
        if CardEngine.isOfferable(settings) {
            Button {
                if hasSmartAccess {
                    showingSubjectDeck = true
                } else {
                    paywallDestination = .typeSubject
                    showingPaywall = true
                }
            } label: {
                Label(hasSmartAccess ? "Type a Subject" : "Type a Subject (Pro)",
                      systemImage: "sparkles")
            }
            Button {
                if hasSmartAccess {
                    showingPhotoDeck = true
                } else {
                    paywallDestination = .scanPage
                    showingPaywall = true
                }
            } label: {
                Label(hasSmartAccess ? "Scan a Page" : "Scan a Page (Pro)",
                      systemImage: "doc.viewfinder")
            }
        }
        Button {
            showingNewDeck = true
        } label: {
            Label("Blank Deck", systemImage: "square.and.pencil")
        }
        // Add a deck a friend shared with you as a .flipstudy file.
        Button {
            showingImporter = true
        } label: {
            Label("Add a Shared Deck", systemImage: "square.and.arrow.down")
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

/// Today at a glance: the streak and progress toward the daily goal.
private struct ProgressHeader: View {
    let streak: Int
    let reviewed: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if streak > 0 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .foregroundStyle(.orange)
                } else {
                    Label("Study today to start a streak", systemImage: "flame")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(reviewed >= goal ? "Goal met!" : "\(reviewed) of \(goal) today")
                    .foregroundStyle(reviewed >= goal ? .green : .secondary)
            }
            .font(.subheadline.weight(.semibold))
            ProgressView(value: Double(min(reviewed, goal)), total: Double(max(goal, 1)))
                .tint(reviewed >= goal ? .green : .accentColor)
        }
        .padding(.vertical, 4)
    }
}

/// Identifiable box so a decoded snapshot can drive `.sheet(item:)`.
private struct PendingDeck: Identifiable {
    let id = UUID()
    let deck: SharedDeck
}

/// "Add this deck?" preview shown before a shared deck is added, so nothing is
/// created behind the user's back. Lists the title and a scrollable look at the
/// cards, with Add / Cancel.
private struct ImportDeckSheet: View {
    let deck: SharedDeck
    let onAdd: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deck.title.isEmpty ? "Untitled Deck" : deck.title)
                            .font(.headline)
                        Text("^[\(deck.cards.count) card](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("This adds a new copy to your decks. Your existing decks aren't changed.")
                }

                if !deck.cards.isEmpty {
                    Section("Cards") {
                        ForEach(Array(deck.cards.enumerated()), id: \.offset) { _, card in
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
                }
            }
            .navigationTitle("Add This Deck?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { onAdd() }
                        .disabled(deck.cards.isEmpty)
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(ProStore())
        .environment(FamilyLinkRouter())
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self, StudyDay.self], inMemory: true)
}
