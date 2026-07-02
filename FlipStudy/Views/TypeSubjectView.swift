import SwiftUI
import SwiftData
import Translation

/// Create a deck by typing a topic and letting the on-device AI draft the cards.
/// The result is a preview the user reviews before the deck is actually made —
/// AI never silently creates content a child studies.
///
/// English decks are plain question/answer cards written by the on-device model.
/// Picking another answer language makes a vocabulary deck: the model supplies
/// an English term list and a translation engine (Apple on-device by default, or
/// a parent-enabled cloud engine) fills in the answer language. English is always
/// the base language, so the front of every card is English.
struct TypeSubjectView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var topic = ""
    @State private var title = ""
    @State private var answerLanguage: AnswerLanguage = .english
    @State private var draftCards: [(front: String, back: String)] = []
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var hasGenerated = false

    // Apple's translator vends its session through `.translationTask`, so the
    // English terms wait here until that closure runs.
    @State private var pendingTerms: [String] = []
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var lastConfiguredLanguage: AnswerLanguage?

    private var settings: AppSettings? { settingsList.first }

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
                    TextField("Topic (e.g. French food vocabulary)", text: $topic, axis: .vertical)
                        .lineLimit(1...3)
                    Picker("Answer language", selection: $answerLanguage) {
                        ForEach(AnswerLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    Button {
                        generate()
                    } label: {
                        if isGenerating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(answerLanguage.isTranslation ? "Making & translating…" : "Making cards…")
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
            .translationTask(translationConfig) { session in
                await runAppleTranslation(session: session)
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
        if answerLanguage.isTranslation {
            return "Cards are made on your device, then translated to \(answerLanguage.label) using \(provider.label). Review them below before you create the deck."
        }
        return "Cards are made on your device — free and private. Review them below before you create the deck."
    }

    // MARK: - Generation

    private func generate() {
        errorMessage = nil
        isGenerating = true
        let requestedTopic = trimmedTopic
        if answerLanguage.isTranslation {
            generateTranslated(topic: requestedTopic)
        } else {
            generateQA(topic: requestedTopic)
        }
    }

    /// English deck: plain question/answer cards straight from the model.
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

    /// Language deck: model writes English terms, then a translator fills the
    /// answer language. Apple runs through `.translationTask`; cloud runs inline.
    private func generateTranslated(topic requestedTopic: String) {
        Task {
            do {
                let terms = try await AICardGenerator.makeEnglishTerms(topic: requestedTopic)
                pendingTerms = terms
                if trimmedTitle.isEmpty { title = requestedTopic }
                if provider.isCloud {
                    await runCloudTranslation()
                } else {
                    startAppleTranslation()
                }
            } catch {
                draftCards = []
                errorMessage = error.localizedDescription
                hasGenerated = true
                isGenerating = false
            }
        }
    }

    /// Kick off (or re-run) the Apple translation session. Changing languages
    /// makes a new configuration; repeating the same language re-runs the old one.
    private func startAppleTranslation() {
        if lastConfiguredLanguage == answerLanguage, translationConfig != nil {
            translationConfig?.invalidate()
        } else {
            translationConfig = TranslationSession.Configuration(
                source: Locale.Language(identifier: "en"),
                target: answerLanguage.locale)
            lastConfiguredLanguage = answerLanguage
        }
    }

    private func runAppleTranslation(session: TranslationSession) async {
        guard !pendingTerms.isEmpty else { return }
        do {
            let translator = AppleTranslator(session: session)
            let translations = try await translator.translate(pendingTerms)
            buildTranslatedCards(terms: pendingTerms, translations: translations)
        } catch {
            draftCards = []
            errorMessage = error.localizedDescription
        }
        hasGenerated = true
        isGenerating = false
    }

    private func runCloudTranslation() async {
        do {
            guard let settings, settings.cloudAIEnabled else {
                throw CloudTranslationError.notEnabled
            }
            let translator = CloudTranslator(provider: provider,
                                             apiKey: CloudTranslationKey.read(),
                                             target: answerLanguage)
            let translations = try await translator.translate(pendingTerms)
            buildTranslatedCards(terms: pendingTerms, translations: translations)
        } catch {
            draftCards = []
            errorMessage = error.localizedDescription
        }
        hasGenerated = true
        isGenerating = false
    }

    /// Pair each English term with its translation, dropping any that came back
    /// empty so a child never sees a half-blank card.
    private func buildTranslatedCards(terms: [String], translations: [String]) {
        let cards = zip(terms, translations).compactMap { term, translated -> (front: String, back: String)? in
            let back = translated.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !back.isEmpty else { return nil }
            return (front: term, back: back)
        }
        draftCards = cards
        if cards.isEmpty {
            errorMessage = "Couldn't translate the terms. Check the translation engine in Settings."
        }
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
