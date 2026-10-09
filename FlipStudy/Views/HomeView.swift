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
    @AppStorage(AppTheme.storageKey, store: AppTheme.defaults) private var themeRaw = AppTheme.classic.rawValue
    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .classic }
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
    /// Long-pressing a deck asks before deleting it; with sync on, it goes
    /// from every device.
    @State private var deckToDelete: Deck?

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
                    VStack(spacing: 18) {
                        Text("🃏")
                            .font(.system(size: 84))
                        Text("Let's make your first deck!")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Fill it with cards, then flip, type, quiz or match your way through them.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Menu {
                            newDeckMenuItems
                        } label: {
                            Label("New Deck", systemImage: "plus")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 30)
                                .padding(.vertical, 15)
                                .background(theme.gradient, in: Capsule())
                                .shadow(color: theme.bottom.opacity(0.4), radius: 8, y: 4)
                        }
                        .padding(.top, 6)
                    }
                    .padding(32)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ProgressHeader(streak: streak, reviewed: reviewedToday, goal: dailyGoal, theme: theme)
                            Text("My Decks")
                                .font(.title2.bold())
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                                GridItem(.flexible(), spacing: 14)],
                                      spacing: 14) {
                                ForEach(decks) { deck in
                                    NavigationLink(value: deck) {
                                        DeckTile(deck: deck)
                                    }
                                    .buttonStyle(SquishButtonStyle())
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            deckToDelete = deck
                                        } label: {
                                            Label("Delete Deck", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .confirmationDialog(
                "Delete “\(deckToDelete?.title ?? "")”?",
                isPresented: Binding(get: { deckToDelete != nil }, set: { if !$0 { deckToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Deck", role: .destructive) {
                    if let deckToDelete { context.delete(deckToDelete) }
                    deckToDelete = nil
                }
            } message: {
                Text("Its cards are deleted too, on every device that syncs with this one.")
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

}

/// A deck as a big, bright tile: its emoji, title, size, and what's due.
private struct DeckTile: View {
    let deck: Deck

    var body: some View {
        let palette = deck.palette
        let count = deck.allCards.count
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(deck.displayEmoji)
                    .font(.system(size: 40))
                Spacer()
                if deck.dueCount > 0 {
                    Text("\(deck.dueCount) due")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(.white, in: Capsule())
                }
            }
            Spacer(minLength: 0)
            Text(deck.title)
                .font(.headline.weight(.bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Text("^[\(count) card](inflect: true)")
                .font(.caption.weight(.semibold))
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(palette.gradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: palette.bottom.opacity(0.35), radius: 8, y: 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.title), \(count) cards\(deck.dueCount > 0 ? ", \(deck.dueCount) due" : "")")
    }
}

/// Today at a glance: the streak, and a ring filling toward the daily goal.
private struct ProgressHeader: View {
    let streak: Int
    let reviewed: Int
    let goal: Int
    let theme: AppTheme

    private var goalMet: Bool { reviewed >= goal }

    private var background: LinearGradient {
        if goalMet { return DeckPalette.mint.gradient }
        if streak > 0 {
            return LinearGradient(colors: [DeckPalette.tangerine.top, DeckPalette.berry.bottom],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return theme.gradient
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                if streak > 0 {
                    HStack(spacing: 4) {
                        Text("🔥")
                            .font(.system(size: 34))
                        Text("\(streak)")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                    }
                    Text(streak == 1 ? "day streak — come back tomorrow!" : "day streak — keep it going!")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text("✨")
                        .font(.system(size: 34))
                    Text("Study today to start a streak!")
                        .font(.headline)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.3), lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(Double(reviewed) / Double(max(goal, 1)), 1))
                    .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: reviewed)
                if goalMet {
                    Image(systemName: "checkmark")
                        .font(.title2.weight(.heavy))
                } else {
                    VStack(spacing: -2) {
                        Text("\(reviewed)")
                            .font(.title3.weight(.heavy))
                            .contentTransition(.numericText())
                        Text("of \(goal)")
                            .font(.caption2.weight(.semibold))
                    }
                }
            }
            .frame(width: 78, height: 78)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streak > 0 ? "\(streak)-day streak. \(reviewed) of \(goal) cards today." : "No streak yet. \(reviewed) of \(goal) cards today.")
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
