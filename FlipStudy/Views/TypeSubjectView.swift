import SwiftUI
import SwiftData
import Translation

/// Create a deck by typing a topic and letting the on-device AI draft the cards.
/// The result is a preview the user reviews before the deck is actually made —
/// AI never silently creates content a child studies.
///
/// The model is only ever asked for **English** items (its strongest, most
/// reliable language). A `Translator` then produces each card's front (base
/// language) and back (translation language) from those English concepts, so the
/// two sides can never collapse to the same language and the words come from a
/// real translation engine. When both languages match it's a plain English
/// question/answer deck written directly by the model instead.
struct TypeSubjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var topic = ""
    @State private var title = ""
    /// Language shown on the front of each card.
    @State private var baseLanguage: AnswerLanguage = .english
    /// Language shown on the back of each card.
    @State private var targetLanguage: AnswerLanguage = .italian
    /// Whether cards are single words or full phrases (enforced, not guessed).
    @State private var deckStyle: DeckStyle = .phrases
    @State private var draftCards: [(front: String, back: String)] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var hasGenerated = false

    // The model's English items, and each side once resolved into its language.
    // A side is `nil` until ready; when both are ready the cards are assembled.
    @State private var englishConcepts: [String] = []
    @State private var frontResolved: [String]?
    @State private var backResolved: [String]?

    // Apple's translator vends its session through `.translationTask`; each side
    // that needs translating gets its own config (English → that language).
    @State private var frontConfig: TranslationSession.Configuration?
    @State private var backConfig: TranslationSession.Configuration?
    @State private var lastFrontTarget: AnswerLanguage?
    @State private var lastBackTarget: AnswerLanguage?

    private let sourceLanguage = Locale.Language(identifier: "en")

    private var settings: AppSettings? { settingsList.first }

    /// A translation deck is made whenever the two languages differ.
    private var needsTranslation: Bool { baseLanguage != targetLanguage }

    private var provider: TranslationProvider {
        settings?.translationProvider ?? .apple
    }

    private var trimmedTopic: String {
        topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedTopic.isEmpty && !isGenerating
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !draftCards.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Topic (e.g. Italian phrases for tourists)", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Base language", selection: $baseLanguage) {
                        ForEach(AnswerLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    Picker("Translation language", selection: $targetLanguage) {
                        ForEach(AnswerLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    Picker("Card style", selection: $deckStyle) {
                        ForEach(DeckStyle.allCases) { style in
                            Text(style.label).tag(style)
                        }
                    }
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(needsTranslation ? "Making & translating…" : "Making cards…")
                            }
                        } else {
                            Label("Generate Cards", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canGenerate)
                } header: {
                    Text("Topic")
                } footer: {
                    Text(generatorFootnote)
                }

                if let unavailable = AICardGenerator.unavailableReason {
                    Section {
                        Label(unavailable, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !draftCards.isEmpty {
                    Section("Deck") {
                        TextField("Deck title", text: $title)
                    }

                    Section("Preview (\(draftCards.count))") {
                        ForEach(Array(draftCards.enumerated()), id: \.offset) { _, card in
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
                } else if hasGenerated && !isGenerating && errorMessage == nil {
                    Section {
                        Text("No cards yet. Try rewording the topic.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Type a Subject")
            .navigationBarTitleDisplayMode(.inline)
            .translationTask(frontConfig) { session in
                await resolveFront(session: session)
            }
            .translationTask(backConfig) { session in
                await resolveBack(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
        }
    }

    private var generatorFootnote: String {
        if needsTranslation {
            return "The AI writes the ideas in English on your device, then \(provider.label) translates the front to \(baseLanguage.label) and the back to \(targetLanguage.label). Review them below before you create the deck."
        }
        return "Cards are made on your device — free and private. Review them below before you create the deck."
    }

    // MARK: - Generation

    private func generate() {
        errorMessage = nil
        isGenerating = true
        hasGenerated = false
        draftCards = []
        frontResolved = nil
        backResolved = nil
        let requestedTopic = trimmedTopic
        if needsTranslation {
            generateTranslated(topic: requestedTopic)
        } else {
            generateQA(topic: requestedTopic)
        }
    }

    /// Same-language deck: plain question/answer cards straight from the model.
    private func generateQA(topic requestedTopic: String) {
        Task {
            do {
                let cards = try await AICardGenerator.makeCards(topic: requestedTopic)
                draftCards = cards
                if trimmedTitle.isEmpty { title = requestedTopic }
            } catch {
                draftCards = []
                errorMessage = error.localizedDescription
            }
            hasGenerated = true
            isGenerating = false
        }
    }

    /// Translation deck: the model writes English concepts; the translator then
    /// fills the front (base language) and back (translation language). Any side
    /// that is already English uses the concepts as-is.
    private func generateTranslated(topic requestedTopic: String) {
        Task {
            do {
                let concepts = try await AICardGenerator.makeConcepts(topic: requestedTopic, style: deckStyle)
                englishConcepts = concepts
                if trimmedTitle.isEmpty { title = requestedTopic }

                frontResolved = baseLanguage == .english ? concepts : nil
                backResolved = targetLanguage == .english ? concepts : nil

                if provider.isCloud {
                    await runCloudResolution()
                } else {
                    if baseLanguage != .english { triggerFront() }
                    if targetLanguage != .english { triggerBack() }
                    assembleIfReady()
                }
            } catch {
                fail(error)
            }
        }
    }

    // MARK: - Apple on-device translation (one side per config)

    private func triggerFront() {
        if lastFrontTarget == baseLanguage, frontConfig != nil {
            frontConfig?.invalidate()
        } else {
            frontConfig = TranslationSession.Configuration(source: sourceLanguage, target: baseLanguage.locale)
            lastFrontTarget = baseLanguage
        }
    }

    private func triggerBack() {
        if lastBackTarget == targetLanguage, backConfig != nil {
            backConfig?.invalidate()
        } else {
            backConfig = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage.locale)
            lastBackTarget = targetLanguage
        }
    }

    private func resolveFront(session: TranslationSession) async {
        guard !englishConcepts.isEmpty, baseLanguage != .english else { return }
        do {
            frontResolved = try await AppleTranslator(session: session).translate(englishConcepts)
        } catch {
            fail(error)
            return
        }
        assembleIfReady()
    }

    private func resolveBack(session: TranslationSession) async {
        guard !englishConcepts.isEmpty, targetLanguage != .english else { return }
        do {
            backResolved = try await AppleTranslator(session: session).translate(englishConcepts)
        } catch {
            fail(error)
            return
        }
        assembleIfReady()
    }

    // MARK: - Cloud translation

    private func runCloudResolution() async {
        do {
            guard let settings, settings.cloudAIEnabled else {
                throw CloudTranslationError.notEnabled
            }
            let key = CloudTranslationKey.read()
            let region = settings.cloudTranslationRegion
            if baseLanguage != .english {
                frontResolved = try await CloudTranslator(provider: provider, apiKey: key,
                                                          source: .english, target: baseLanguage,
                                                          region: region)
                    .translate(englishConcepts)
            }
            if targetLanguage != .english {
                backResolved = try await CloudTranslator(provider: provider, apiKey: key,
                                                         source: .english, target: targetLanguage,
                                                         region: region)
                    .translate(englishConcepts)
            }
            assembleIfReady()
        } catch {
            fail(error)
        }
    }

    // MARK: - Assembly

    /// Build cards once both sides are resolved, pairing them by index and
    /// dropping any where either side came back empty.
    private func assembleIfReady() {
        guard let fronts = frontResolved, let backs = backResolved else { return }
        let cards = zip(fronts, backs).compactMap { front, back -> (front: String, back: String)? in
            let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
            let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !f.isEmpty, !b.isEmpty else { return nil }
            return (front: f, back: b)
        }
        draftCards = cards
        if cards.isEmpty {
            errorMessage = "Couldn't build cards. Try a different topic or translation engine."
        }
        hasGenerated = true
        isGenerating = false
    }

    private func fail(_ error: Error) {
        draftCards = []
        errorMessage = error.localizedDescription
        hasGenerated = true
        isGenerating = false
    }

    // MARK: - Persistence

    private func create() {
        let deck = Deck(title: trimmedTitle,
                        subject: trimmedTopic,
                        source: .typedSubject)
        context.insert(deck)
        for draft in draftCards {
            let card = Card(front: draft.front, back: draft.back)
            card.deck = deck
            context.insert(card)
        }
        dismiss()
    }
}
