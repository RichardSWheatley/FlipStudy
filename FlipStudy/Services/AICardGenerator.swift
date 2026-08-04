import Foundation
import FoundationModels
import NaturalLanguage

/// Turns a plain-language topic into draft flashcards using Apple's on-device
/// Foundation Model. Everything runs locally — no network, no API key — so it's
/// free and private, which is why it's the default (non-gated) AI path.
enum AICardGenerator {

    /// A single generated card. `@Generable` lets the model fill it directly
    /// via guided generation, so we never parse free-form text.
    @Generable
    struct DraftCard {
        @Guide(description: "A short question or term for the front of the card")
        var front: String
        @Guide(description: "A concise answer or definition for the back, one or two sentences")
        var back: String
    }

    @Generable
    struct DraftDeck {
        @Guide(description: "The flashcards for this topic")
        var cards: [DraftCard]
    }

    /// A list of English vocabulary terms for a topic. Used for language decks:
    /// the model only supplies the English side, and Apple's translator fills in
    /// the answer language, so the vocabulary matches a real translation engine
    /// rather than the model's own (sometimes off) word choices.
    @Generable
    struct TermList {
        @Guide(description: "One English item to learn — a single word, a phrase, or a whole sentence, as long as it naturally needs to be. No translation, no numbering.")
        var terms: [String]
    }

    enum GenerationError: LocalizedError {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case empty

        var errorDescription: String? {
            switch self {
            case .deviceNotEligible:
                return "This device can't run on-device AI. You can still add cards by hand or scan a page."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to make cards with AI."
            case .modelNotReady:
                return "The AI model is still getting ready. Try again in a little while."
            case .empty:
                return "The AI didn't return any cards. Try rewording the topic."
            }
        }
    }

    /// Whether on-device generation can run right now.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Whether this *hardware* can ever run on-device generation. False only when
    /// the device model lacks Apple Intelligence (e.g. a base iPhone 15) — as
    /// opposed to it merely being turned off or still downloading, which a user
    /// can fix in Settings. Used to hide AI-only entry points on ineligible
    /// devices instead of offering a button that can never work, while keeping
    /// the option on capable devices where it's just a toggle or download away.
    static var isDeviceEligible: Bool {
        if case .unavailable(.deviceNotEligible) = SystemLanguageModel.default.availability {
            return false
        }
        return true
    }

    /// A user-facing reason the feature is unavailable, or nil if it's ready.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return GenerationError.deviceNotEligible.errorDescription
        case .unavailable(.appleIntelligenceNotEnabled):
            return GenerationError.appleIntelligenceNotEnabled.errorDescription
        case .unavailable(.modelNotReady):
            return GenerationError.modelNotReady.errorDescription
        case .unavailable:
            return GenerationError.modelNotReady.errorDescription
        }
    }

    /// Throws the matching `GenerationError` if the on-device model can't run,
    /// so each entry point shares one availability gate.
    private static func requireAvailable() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(.deviceNotEligible):
            throw GenerationError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw GenerationError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw GenerationError.modelNotReady
        case .unavailable:
            throw GenerationError.modelNotReady
        }
    }

    static func makeCards(topic: String, count: Int = 12) async throws -> [(front: String, back: String)] {
        try requireAvailable()

        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Create \(count) study flashcards about: \(topic).
        Each card has a short prompt on the front and a concise answer on the \
        back. Keep them factual and suitable for a student.
        """
        let response = try await session.respond(to: prompt, generating: DraftDeck.self)

        let cards = response.content.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty }
        guard !cards.isEmpty else { throw GenerationError.empty }
        return cards
    }

    /// Turn a page of recognized (OCR) text into study flashcards. The text can
    /// be anything a page holds — a textbook paragraph, a worksheet, a glossary,
    /// lecture notes — so the model's job is to *understand* the content and pull
    /// out the useful question/answer pairs, not to split lines mechanically.
    /// Cards are drafts the user reviews before the deck is made.
    /// The cap is higher than the typed-topic one: a topic invents cards and 12
    /// is a sensible study set, but a scanned page has however much content it
    /// has, and silently dropping the back half of a worksheet reads as the
    /// scanner being bad at its job.
    static func makeCards(fromText text: String, count: Int = 24) async throws -> [(front: String, back: String)] {
        try requireAvailable()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerationError.empty }

        let session = LanguageModelSession(instructions: scanInstructions)
        let prompt = """
        Below is text captured from a page by OCR. Study it and create up to \
        \(count) flashcards that capture the most useful facts, terms, and ideas \
        a student should learn from it. Decide for yourself what the material is \
        about; do not assume a subject. If the page already pairs terms with \
        definitions or questions with answers, use those pairings. Otherwise, \
        write a clear question or term for the front and a concise answer for the \
        back. Ignore page numbers, headers, and other noise. If the text has no \
        studiable content, return no cards.

        PAGE TEXT:
        \(trimmed)
        """
        let response = try await session.respond(to: prompt, generating: DraftDeck.self)

        let cards = response.content.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty }
        guard !cards.isEmpty else { throw GenerationError.empty }
        return cards
    }

    /// Pull the vocabulary items off a scanned page. The page is a list of
    /// words/phrases to learn (not Q&A material), so the model's job is only to
    /// find and clean the items — numbering, page furniture, and OCR junk are
    /// dropped — never to answer or explain them. Items come back in English for
    /// the same reason as `makeConcepts`: a real translator fills in the other
    /// language afterward.
    static func makeTerms(fromText text: String, count: Int = 25) async throws -> [String] {
        try requireAvailable()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GenerationError.empty }

        let session = LanguageModelSession(instructions: vocabScanInstructions)
        let prompt = """
        Below is text captured by OCR. It may be a photographed page or a \
        screenshot of an app, so alongside the vocabulary it can contain \
        interface junk: clock times, battery numbers, app and button names \
        (like "Ask", "Search", "Send"), model or product names, navigation \
        labels, and stray symbols. None of that is vocabulary — leave it out.

        List up to \(count) of the English words and phrases the student wants \
        to learn, each exactly as it appears (fixing obvious OCR slips like a \
        scrambled word you can confidently restore). If an item is garbled \
        beyond recognition, leave it out. Do not answer, define, or translate \
        anything.

        OCR TEXT:
        \(trimmed)
        """
        let response = try await session.respond(to: prompt, generating: TermList.self)

        var seen = Set<String>()
        var items: [String] = []
        for term in response.content.terms {
            guard let cleaned = tidyTerm(term), seen.insert(cleaned.lowercased()).inserted else { continue }
            items.append(cleaned)
        }
        guard !items.isEmpty else { throw GenerationError.empty }
        return items
    }

    /// Deterministic cleanup for a vocabulary item, applied no matter where the
    /// item came from (model output or the fallback line parser): strips
    /// numbering and bullet punctuation, and rejects entries with no letters,
    /// single characters, and status-bar artifacts like clock times. The model
    /// is *asked* to do all this, but a guard in code means one slipped item
    /// can't become a junk card.
    static func tidyTerm(_ raw: String) -> String? {
        var term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        term = term.replacingOccurrences(of: #"^\d+[.)]?\s*"#, with: "", options: .regularExpression)
        term = term.replacingOccurrences(of: #"^[•\-*–—·=+]+\s*"#, with: "", options: .regularExpression)
        term = TextCleanup.stripEdgeQuotes(term)
        guard term.count >= 2,
              term.rangeOfCharacter(from: .letters) != nil,
              term.range(of: #"^\d{1,2}:\d{2}"#, options: .regularExpression) == nil
        else { return nil }
        return term
    }

    /// Produce study items for a topic, **always in English** — the model's
    /// strongest language. Callers hand these to a `Translator` to fill in each
    /// card's languages, so the words come from a real translation engine and the
    /// front/back can never collapse to the same language.
    ///
    /// The model is unreliable at obeying "write in language X", so we don't trust
    /// it: anything the language detector flags as clearly non-English is dropped,
    /// and `style` is enforced by a hard word-count filter (Phrases never yields a
    /// lone word). What comes back is guaranteed English and on-style.
    static func makeConcepts(topic: String, style: DeckStyle, count: Int = 12) async throws -> [String] {
        try requireAvailable()

        let styleLine: String
        let example: String
        switch style {
        case .phrases:
            styleLine = "Each item MUST be a complete, natural English phrase or sentence of several words — never a single word."
            example = """
            Where is the bathroom?
            How much does this cost?
            I would like a coffee, please.
            Can you help me?
            """
        case .words:
            styleLine = "Each item is a single English word or a very short term."
            example = """
            water
            train station
            thank you
            expensive
            """
        case .sentenceStarters:
            styleLine = "Each item MUST be a short English SENTENCE OPENER — the first few words a sentence commonly begins with, left unfinished so the learner can complete it. Two to four words each. Do NOT write complete sentences."
            example = """
            I would like
            Can you tell me
            I'm trying to
            Do you know where
            """
        }

        let session = LanguageModelSession(instructions: conceptInstructions)
        let prompt = """
        Study topic: \(topic)

        In ENGLISH ONLY, list \(count) useful items to study for this topic. \
        Ignore any language or country named in the topic — that only tells you \
        the subject; you must still write in English. \(styleLine)

        Worked example — topic "Italian phrases for tourists". Correct English \
        output (English even though the topic is about Italian):
        \(example)

        Now list the \(count) English items for the topic above. No numbering, no \
        translations, no notes — English only.
        """
        let response = try await session.respond(to: prompt, generating: TermList.self)

        var seen = Set<String>()
        var items: [String] = []

        // Sentence-starter decks always begin from the same reliable basics
        // (the same list for every language), then the model's suggestions are
        // appended so each deck also gets some topic-flavoured openers.
        if style == .sentenceStarters {
            for starter in DeckStyle.basicStarters where seen.insert(starter.lowercased()).inserted {
                items.append(starter)
            }
        }

        for term in response.content.terms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  isProbablyEnglish(cleaned),
                  style.accepts(cleaned),
                  seen.insert(cleaned.lowercased()).inserted
            else { continue }
            items.append(cleaned)
        }

        guard !items.isEmpty else { throw GenerationError.empty }
        return items
    }

    /// Reject text that the language detector is confident is *not* English.
    /// Short strings are easy to misjudge, so we only drop an item when another
    /// language clearly dominates — otherwise we keep it to avoid false drops.
    private static func isProbablyEnglish(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let english = hypotheses[.english] ?? 0
        if let top = hypotheses.max(by: { $0.value < $1.value }),
           top.key != .english, top.value > 0.65, english < 0.25 {
            return false
        }
        return true
    }

    private static let instructions = """
    You are a helpful study assistant that writes clear, accurate flashcards.
    Fronts are brief terms or questions. Backs are short, correct answers or
    definitions. Avoid trick questions and keep the language age-appropriate.
    """

    private static let scanInstructions = """
    You turn raw text scanned from a page into accurate study flashcards. Read
    the material, work out what it is teaching, and extract the question/answer
    or term/definition pairs a student would actually want to memorize. Fix
    obvious OCR slips when you're confident, keep answers short and correct, and
    leave out page furniture like headers, page numbers, and stray fragments.
    Never invent facts that aren't supported by the text.
    """

    private static let vocabScanInstructions = """
    You clean up vocabulary lists captured by OCR from pages and screenshots.
    The student already chose these words and phrases — your only job is to
    return them as a tidy list. Never answer, define, translate, or expand an
    item, and never invent new ones. Be strict about what counts as vocabulary:
    app names, button labels, menu items, status-bar times and numbers, and
    stray OCR fragments are never vocabulary, and a garbled token you cannot
    confidently restore to a real word is dropped, not kept.
    """

    private static let conceptInstructions = """
    You build English study lists for language learners. Always write in English,
    no matter what language or country the topic mentions — that is only the
    subject; a separate translator adds the other language afterward. Give the most
    useful items first, follow the requested style exactly (single words, or full
    phrases and sentences), and output nothing but the English items — no
    translations, no numbering, no notes.
    """
}
