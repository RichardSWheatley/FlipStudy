import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import Translation

/// Create a deck by scanning a page (device camera) or picking a photo, running
/// on-device OCR, then turning the recognized text into draft cards. The AI
/// extractor reads the page into real question/answer pairs — scanning is an
/// Apple Intelligence feature, gated at the New Deck menu, and there is no
/// rule-based fallback: when the model can't run or fails, the screen says why
/// instead of producing junk cards. The one deterministic path kept is a page
/// that already pairs each term with its translation — those pairs are the
/// page's own content, taken verbatim.
///
/// Optionally the answers can be translated into another language: the English
/// question stays on the front and its answer is translated onto the back, so a
/// scanned English Q&A sheet becomes a language deck. Either way the cards are a
/// preview the user reviews and edits before the deck is created.
struct PhotoDeckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    @State private var title = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var extractedText = ""
    @State private var isRecognizing = false
    @State private var isGenerating = false
    @State private var showScanner = false
    @State private var errorMessage: String?
    @State private var draftCards: [(front: String, back: String)] = []

    /// What kind of content the page holds. Questions & answers get the Q&A
    /// extractor; a vocabulary list gets each word/phrase as a card front with
    /// its translation on the back — the same kind of deck Type a Subject makes.
    enum PageKind: String, CaseIterable, Identifiable {
        case questions, vocabulary
        var id: String { rawValue }
        var label: String {
            switch self {
            case .questions: "Questions & answers"
            case .vocabulary: "Vocabulary to translate"
            }
        }
    }

    @State private var pageKind: PageKind = .questions
    /// True once the user has picked the page kind themselves; stops the
    /// auto-detection from overriding an explicit choice.
    @State private var userChosePageKind = false
    /// True when the scanned page already pairs each term with its translation
    /// ("Good Morning - Buongiorno"). The page's own pairs become the cards
    /// as-is — no generation, no re-translation.
    @State private var pageProvidesPairs = false

    /// The language the answers are translated into. `.english` means no
    /// translation — plain question/answer cards.
    @State private var answerLanguage: AnswerLanguage = .english
    /// True once the user has picked a language themselves; stops the title
    /// inference from overriding an explicit choice.
    @State private var userChoseLanguage = false
    /// The extracted English Q&A, kept so the answers can be re-translated when
    /// the language changes without re-running OCR or the AI extractor.
    @State private var englishCards: [(front: String, back: String)] = []

    // Apple's on-device translator vends its session through `.translationTask`;
    // this config drives the English → answer-language pass over the backs.
    @State private var backConfig: TranslationSession.Configuration?
    @State private var lastBackTarget: AnswerLanguage?

    private let sourceLanguage = Locale.Language(identifier: "en")

    private var settings: AppSettings? { settingsList.first }

    /// Which AI reads the page: the phone's own, or FlipStudy Cloud when a
    /// family code is redeemed. Chosen per render so redeeming (or switching
    /// back) in Settings takes effect immediately.
    private var engine: CardEngine { CardEngine.active(for: settings) }

    private var provider: TranslationProvider {
        settings?.translationProvider ?? .apple
    }

    /// Answers are translated whenever a non-English answer language is chosen.
    private var needsTranslation: Bool { answerLanguage != .english }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedText: String {
        extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canGenerate: Bool {
        !trimmedText.isEmpty && !isRecognizing && !isGenerating
    }

    private var canCreate: Bool {
        !trimmedTitle.isEmpty && !draftCards.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deck") {
                    TextField("Title (e.g. Biology Chapter 3)", text: $title)
                }

                Section {
                    if DocumentScanner.isSupported {
                        Button {
                            showScanner = true
                        } label: {
                            Label("Scan a Page", systemImage: "doc.viewfinder")
                        }
                    }
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Choose a Photo", systemImage: "photo.on.rectangle")
                    }
                } header: {
                    Text("Capture")
                } footer: {
                    Text(captureFootnote)
                }

                Section {
                    Picker("Page holds", selection: pageKindSelection) {
                        ForEach(PageKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                } header: {
                    Text("What's on the Page?")
                } footer: {
                    Text(pageKind == .questions
                         ? "Questions with answers, or facts to study — each becomes a question-and-answer card."
                         : "A list of words or phrases to learn. Each becomes a card front, with its translation on the back.")
                }

                // Scanning is AI-only now. The menu already hides it on
                // hardware that can never run the model, but availability is
                // dynamic (Apple Intelligence toggled off, model still
                // downloading) — so if the model can't run right now, say why
                // up front rather than failing at Make Cards.
                if let reason = engine.unavailableReason {
                    Section {
                        Label {
                            Text(reason)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        .font(.callout)
                    }
                }

                if isRecognizing {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading text…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if !trimmedText.isEmpty || isRecognizing {
                    Section {
                        Picker(pageKind == .questions ? "Answer language" : "Translate into",
                               selection: languageSelection) {
                            ForEach(AnswerLanguage.allCases) { language in
                                Text(language.label).tag(language)
                            }
                        }
                    } header: {
                        Text(pageKind == .questions ? "Translate Answers" : "Translate Words")
                    } footer: {
                        Text(translationFootnote)
                    }

                    Section {
                        TextEditor(text: $extractedText)
                            .frame(minHeight: 140)
                            .font(.body)
                        Button {
                            generateCards()
                        } label: {
                            if isGenerating {
                                HStack(spacing: 10) {
                                    ProgressView()
                                    Text("Making cards…")
                                }
                            } else {
                                Label(draftCards.isEmpty ? "Make Cards" : "Redo Cards",
                                      systemImage: "rectangle.stack.badge.plus")
                            }
                        }
                        .disabled(!canGenerate)
                    } header: {
                        Text("Recognized Text")
                    } footer: {
                        Text(recognizedFootnote)
                    }
                }

                if !draftCards.isEmpty {
                    Section {
                        ForEach(Array(checkedCards.enumerated()), id: \.offset) { index, card in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.front)
                                    .font(.body.weight(.medium))
                                if !card.back.isEmpty {
                                    Text(card.back)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                // Say what looks wrong rather than dropping the
                                // card silently — the user can see the page and
                                // decide far better than a heuristic can.
                                ForEach(card.issues, id: \.self) { issue in
                                    Label(issue.label, systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    remove(at: index)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("Preview (\(draftCards.count))")
                    } footer: {
                        Text(previewFootnote)
                    }

                    if suspectCount > 0 {
                        Section {
                            Button(role: .destructive) {
                                removeSuspectCards()
                            } label: {
                                Label("^[Remove \(suspectCount) flagged card](inflect: true)",
                                      systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scan a Deck")
            .navigationBarTitleDisplayMode(.inline)
            .translationTask(backConfig) { session in
                await resolveBackTranslation(session: session)
            }
            .onChange(of: answerLanguage) { _, _ in
                // Re-translate the already-extracted English cards without
                // re-running OCR or the AI extractor.
                guard !englishCards.isEmpty else { return }
                applyTranslation()
            }
            .onChange(of: pageKind) { _, _ in
                // Q&A extraction and vocabulary extraction read the page
                // differently, so switching modes redoes the cards.
                guard !trimmedText.isEmpty, !isGenerating else { return }
                generateCards()
            }
            .onChange(of: title) { _, newTitle in
                // A title like "Italian Vocab" names the language the user wants —
                // follow it unless they've already picked one by hand.
                guard !userChoseLanguage,
                      let inferred = AnswerLanguage.named(in: newTitle),
                      inferred != answerLanguage else { return }
                answerLanguage = inferred
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
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner { images in
                    showScanner = false
                    recognize(images: images)
                } onCancel: {
                    showScanner = false
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPickedImage(newItem) }
            }
        }
    }

    private func loadPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = "Couldn't load that photo."
                return
            }
            recognize(images: [image])
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var captureFootnote: String {
        // The privacy claim has to track the engine. Reading the page is always
        // on-device (Vision); only the recognized text travels, and only when
        // FlipStudy Cloud is the one writing the cards.
        switch engine {
        case .onDevice:
            return "Text is read on your device — nothing leaves your phone. You review every card before the deck is created."
        case .cloud:
            return "Text is read on your device, then sent to FlipStudy Cloud to make the cards. You review every card before the deck is created."
        }
    }

    /// Picker binding that also remembers the choice was the user's own, so
    /// auto-detection never overrides it.
    private var pageKindSelection: Binding<PageKind> {
        Binding(
            get: { pageKind },
            set: { newValue in
                userChosePageKind = true
                pageKind = newValue
            }
        )
    }

    /// Picker binding that also remembers the choice was the user's own, so the
    /// title inference never overrides it.
    private var languageSelection: Binding<AnswerLanguage> {
        Binding(
            get: { answerLanguage },
            set: { newValue in
                userChoseLanguage = true
                answerLanguage = newValue
            }
        )
    }

    /// Every drafted card with whatever the verifier found wrong with it. The
    /// check runs on the drafts, before anything is saved, so a bad card is
    /// caught in the preview instead of on the phone days later.
    private var checkedCards: [CheckedCard] {
        CardVerifier.check(draftCards,
                           expectedBackLanguage: pageProvidesPairs ? nil : answerLanguage)
    }

    private var suspectCount: Int {
        checkedCards.filter(\.isSuspect).count
    }

    // Pluralized by hand: this footer passes through a String, and automatic
    // inflection (`^[...](inflect: true)`) only works in string literals —
    // in a String it reaches the screen as raw markup.
    private var previewFootnote: String {
        switch suspectCount {
        case 0: "These all look right. Swipe a card to delete it before creating the deck."
        case 1: "1 card looks off — check the one marked below, or swipe to delete."
        default: "\(suspectCount) cards look off — check the ones marked below, or swipe to delete."
        }
    }

    private func remove(at index: Int) {
        guard draftCards.indices.contains(index) else { return }
        draftCards.remove(at: index)
    }

    /// Drop everything the verifier flagged, in one action.
    private func removeSuspectCards() {
        let keep = checkedCards.enumerated()
            .filter { !$0.element.isSuspect }
            .map(\.offset)
        draftCards = keep.map { draftCards[$0] }
    }

    /// Footer under the language picker, adapted to the page kind.
    private var translationFootnote: String {
        if pageProvidesPairs {
            return "This page already pairs each term with its translation — the page's own pairs are used, exactly as written."
        }
        switch (pageKind, answerLanguage) {
        case (.questions, .english):
            return "Cards stay in English. Pick a language to translate each answer onto the back."
        case (.questions, _):
            return "The English question stays on the front; its answer is translated into \(answerLanguage.label) on the back."
        case (.vocabulary, .english):
            return "Pick a language to put each word's translation on the back. On English, the backs stay blank."
        case (.vocabulary, _):
            return "Each English word or phrase stays on the front; its \(answerLanguage.label) translation goes on the back."
        }
    }

    private func recognize(images: [UIImage]) {
        guard !images.isEmpty else { return }
        errorMessage = nil
        isRecognizing = true
        Task {
            var lines: [String] = []
            do {
                for image in images {
                    lines += try await TextRecognizer.recognize(image: image)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            // Each capture REPLACES the recognized text — appending left the
            // previous photo's text in the box, so it showed things that were
            // never in the current image. The text is also pre-cleaned before
            // it's shown: status-bar artifacts and other no-letter junk never
            // belonged in the box at all.
            extractedText = Self.cleanedOCRLines(lines).joined(separator: "\n")
            isRecognizing = false
            if !trimmedText.isEmpty {
                // Work out what kind of page this is instead of assuming —
                // unless the user already told us.
                if !userChosePageKind {
                    pageKind = Self.detectPageKind(of: trimmedText)
                }
                generateCards()
            }
        }
    }

    /// Drop OCR lines that can't be content — clock times, battery numbers,
    /// lone symbols — before the text is ever shown or used. Lines with words
    /// pass through verbatim; deciding whether words are junk is the AI's job,
    /// not a heuristic's.
    static func cleanedOCRLines(_ lines: [String]) -> [String] {
        lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // Two characters minimum: a lone "O" is a scanned radio button or
            // stray mark, never content — same floor tidyTerm uses.
            .filter { $0.count >= 2 && $0.rangeOfCharacter(from: .letters) != nil }
    }

    /// Guess the page kind from its shape. Question pages show themselves with
    /// question marks, "Answer:" lines, and multiple-choice letters; a page of
    /// mostly short lines with none of those reads as a vocabulary list.
    static func detectPageKind(of text: String) -> PageKind {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return .questions }

        var questionSignals = 0
        for line in lines {
            if line.contains("?") { questionSignals += 1 }
            if line.range(of: #"(?i)^answer\b"#, options: .regularExpression) != nil { questionSignals += 1 }
            if line.range(of: #"^[A-D][.)]\s"#, options: .regularExpression) != nil { questionSignals += 1 }
        }
        if questionSignals >= 2 { return .questions }

        // No question shapes: if the lines are mostly short (word-list length),
        // it's vocabulary; long prose still reads best as Q&A extraction.
        let shortLines = lines.filter { $0.split(separator: " ").count <= 4 }.count
        return shortLines * 2 >= lines.count ? .vocabulary : .questions
    }

    // MARK: - Card extraction

    /// Turn the recognized text into draft cards. The AI extractor reads the
    /// whole page and writes real question/answer pairs (or tidies a vocab
    /// list). There is deliberately no rule-based fallback: a failure — model
    /// unavailable, page too long, guardrail refusal, nothing studiable — is
    /// shown as a plain-language error, never papered over with junk cards
    /// presented as if the AI wrote them. The exception is a page that already
    /// pairs terms with translations: those pairs are the page's own content
    /// and are used verbatim, no model involved.
    private func generateCards() {
        let text = trimmedText
        guard !text.isEmpty, !isGenerating else { return }
        errorMessage = nil
        isGenerating = true
        draftCards = []
        Task {
            do {
                let cards: [(front: String, back: String)]
                switch pageKind {
                case .questions:
                    cards = try await engine.makeCards(fromText: text)
                case .vocabulary:
                    // A page that already pairs terms with translations
                    // ("Good Morning - Buongiorno") IS the deck — take its
                    // pairs verbatim, before any model or translator gets a
                    // chance to second-guess the page.
                    if let pairs = VocabPairDetector.pairs(from: text) {
                        pageProvidesPairs = true
                        if !userChoseLanguage,
                           let detected = VocabPairDetector.backLanguage(of: pairs) {
                            answerLanguage = detected
                        }
                        cards = pairs
                    } else {
                        // The page is a plain list to learn: the AI tidies the
                        // list, each item becomes a front, and the back is
                        // filled by translation.
                        pageProvidesPairs = false
                        let items = try await engine.makeTerms(fromText: text)
                        cards = items.map { (front: $0, back: $0) }
                    }
                }
                englishCards = cards
                errorMessage = nil
                applyTranslation()
            } catch {
                englishCards = []
                errorMessage = Self.scanErrorMessage(for: error)
                isGenerating = false
            }
        }
    }

    /// The message shown when card extraction fails. `empty` gets scan-specific
    /// wording (the shared message talks about rewording a topic, which makes
    /// no sense for a photographed page); everything else goes through the
    /// generator's own plain-language mapping.
    static func scanErrorMessage(for error: Error) -> String {
        if case AICardGenerator.GenerationError.empty = error {
            return "The AI couldn't find anything to study in this text. Edit the text and redo, or scan a different page."
        }
        return CardEngine.friendlyMessage(for: error)
    }

    // MARK: - Answer translation

    /// Turn the extracted English cards into the previewed cards. With the
    /// answer language set to English this is a straight copy; otherwise the
    /// answers (backs) are translated into the chosen language while the English
    /// question stays on the front, so a scanned English Q&A sheet becomes a
    /// language deck.
    private func applyTranslation() {
        guard !englishCards.isEmpty else { return }
        // The page's own pairs are already finished cards — never re-translate
        // what the page itself provided, whatever the language picker says.
        guard !pageProvidesPairs else {
            draftCards = englishCards
            isGenerating = false
            return
        }
        guard needsTranslation else {
            // Vocabulary with no translation language leaves the backs blank
            // (a word translated into its own language is no card at all).
            draftCards = pageKind == .vocabulary
                ? englishCards.map { (front: $0.front, back: "") }
                : englishCards
            isGenerating = false
            return
        }
        isGenerating = true
        errorMessage = nil
        if provider.isCloud {
            Task { await translateAnswersCloud() }
        } else {
            triggerBackTranslation()
        }
    }

    /// Cloud path: translate the backs with the user's configured engine/key.
    private func translateAnswersCloud() async {
        do {
            guard let settings, settings.cloudAIEnabled else {
                throw CloudTranslationError.notEnabled
            }
            let key = CloudTranslationKey.read(for: provider)
            let region = settings.cloudTranslationRegion
            let backs = englishCards.map { $0.back }
            let translated = try await CloudTranslator(provider: provider, apiKey: key,
                                                       source: .english, target: answerLanguage,
                                                       region: region)
                .translate(backs)
            assemble(translatedBacks: translated)
        } catch {
            fail(error)
        }
    }

    // Apple's on-device translator vends its session through `.translationTask`;
    // (re)configure it to translate the backs into the answer language.
    private func triggerBackTranslation() {
        if lastBackTarget == answerLanguage, backConfig != nil {
            backConfig?.invalidate()
        } else {
            backConfig = TranslationSession.Configuration(source: sourceLanguage, target: answerLanguage.locale)
            lastBackTarget = answerLanguage
        }
    }

    private func resolveBackTranslation(session: TranslationSession) async {
        guard !englishCards.isEmpty, needsTranslation else { return }
        do {
            let translated = try await AppleTranslator(session: session)
                .translate(englishCards.map { $0.back })
            assemble(translatedBacks: translated)
        } catch {
            fail(error)
        }
    }

    /// Pair each English question with its translated answer, dropping any card
    /// whose translated back came back empty.
    private func assemble(translatedBacks: [String]) {
        let cards = zip(englishCards, translatedBacks).compactMap { card, back -> (front: String, back: String)? in
            let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !b.isEmpty else { return nil }
            return (front: card.front, back: b)
        }
        draftCards = cards
        errorMessage = cards.isEmpty ? "Couldn't translate those answers. Try a different language or engine." : nil
        isGenerating = false
    }

    private func fail(_ error: Error) {
        errorMessage = error.localizedDescription
        isGenerating = false
    }

    /// Footer under the recognized text, describing what will happen to it.
    private var recognizedFootnote: String {
        if pageKind == .vocabulary {
            return "Each word or phrase above becomes a card. Edit the list and redo if something was misread."
        }
        switch engine {
        case .onDevice:
            return "The AI reads this text on your device and writes question-and-answer cards. Edit the text above and redo if the cards need tweaking."
        case .cloud:
            return "FlipStudy Cloud reads this text and writes question-and-answer cards. Edit the text above and redo if the cards need tweaking."
        }
    }

    private func create() {
        let deck = Deck(title: trimmedTitle,
                        subject: "",
                        source: .photo)
        context.insert(deck)
        for draft in draftCards {
            let card = Card(front: draft.front, back: draft.back)
            card.deck = deck
            context.insert(card)
        }
        dismiss()
    }
}

extension DocumentScanner {
    /// Whether document scanning is available (camera-equipped hardware only).
    static var isSupported: Bool {
        VNDocumentCameraViewController.isSupported
    }
}
