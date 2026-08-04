import Foundation
import NaturalLanguage

/// Something wrong with a drafted card, in the user's words. These are the
/// failures that have actually reached the phone: a question cut off mid-thought
/// by OCR, a back that never got translated, a card with nothing on the back,
/// the same text on both sides.
enum CardIssue: String, CaseIterable {
    case emptyBack
    case sameOnBothSides
    case duplicate
    case notTranslated
    case looksTruncated
    case tooLongForAPrompt

    /// Shown next to the card in the preview, so the fix is obvious.
    var label: String {
        switch self {
        case .emptyBack: "No answer on the back"
        case .sameOnBothSides: "Front and back are the same"
        case .duplicate: "Repeats an earlier card"
        case .notTranslated: "Back doesn't look translated"
        case .looksTruncated: "Looks cut off"
        case .tooLongForAPrompt: "Too long for a card front"
        }
    }
}

/// A drafted card with whatever is wrong with it.
struct CheckedCard: Equatable {
    let front: String
    let back: String
    let issues: [CardIssue]

    var isSuspect: Bool { !issues.isEmpty }
}

/// Checks drafted cards before the user commits them to a deck.
///
/// Card extraction can go wrong quietly — the model truncates a question, a
/// translation silently fails and leaves English on both sides, OCR splits a
/// line so the "answer" is a fragment. Rather than hoping the extractor is
/// perfect, every draft is checked and anything doubtful is flagged in the
/// preview for the user to fix or remove. Deterministic, so it protects every
/// user on every device, with or without Apple Intelligence.
enum CardVerifier {

    /// Words a sentence does not end on. A card ending in one of these was
    /// almost certainly cut off — the commonest OCR and model failure.
    private static let danglingWords: Set<String> = [
        "a", "an", "the", "and", "or", "but", "of", "to", "in", "on", "at",
        "for", "with", "by", "from", "as", "is", "are", "was", "were", "be",
        "that", "which", "who", "when", "where", "if", "than", "then", "into",
        "about", "over", "under", "between", "because", "so", "its", "their"
    ]

    /// A front longer than this is a paragraph, not a prompt.
    private static let longFrontLimit = 200

    /// Check each card, in order. `expectedBackLanguage` is the language the
    /// backs were supposed to be translated into; pass nil for plain
    /// question-and-answer decks, where the back staying English is correct.
    static func check(_ cards: [(front: String, back: String)],
                      expectedBackLanguage: AnswerLanguage? = nil) -> [CheckedCard] {
        var seenFronts = Set<String>()
        return cards.map { card in
            let front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)
            var issues: [CardIssue] = []

            if back.isEmpty {
                issues.append(.emptyBack)
            } else if front.compare(back, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                issues.append(.sameOnBothSides)
            }

            if !seenFronts.insert(front.lowercased()).inserted {
                issues.append(.duplicate)
            }

            if let target = expectedBackLanguage, target.isTranslation, !back.isEmpty,
               !issues.contains(.sameOnBothSides), !reads(back, as: target) {
                issues.append(.notTranslated)
            }

            if looksTruncated(front) || looksTruncated(back) {
                issues.append(.looksTruncated)
            }

            if front.count > longFrontLimit {
                issues.append(.tooLongForAPrompt)
            }

            return CheckedCard(front: front, back: back, issues: issues)
        }
    }

    /// True when the text ends the way a cut-off line ends: on a dangling
    /// function word, a comma, or an unclosed bracket or quote.
    static func looksTruncated(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.hasSuffix(",") { return true }
        if count(of: "(", in: trimmed) != count(of: ")", in: trimmed) { return true }
        if count(of: "\"", in: trimmed) % 2 != 0 { return true }

        let lastWord = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .last?
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
            .lowercased() ?? ""
        return danglingWords.contains(lastWord)
    }

    private static func count(of character: Character, in text: String) -> Int {
        text.reduce(0) { $1 == character ? $0 + 1 : $0 }
    }

    /// Whether the text plausibly reads as the target language. Short strings
    /// are easy to misjudge, so this only returns false when the recognizer is
    /// confident it is something else — a wrong flag is worse than a missed one.
    private static func reads(_ text: String, as language: AnswerLanguage) -> Bool {
        guard text.count >= 4 else { return true }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        let target = hypotheses[NLLanguage(language.code)] ?? 0
        guard let top = hypotheses.max(by: { $0.value < $1.value }) else { return true }
        if top.key.rawValue == language.code { return true }
        // Something else clearly dominates and the target barely registers.
        return !(top.value > 0.75 && target < 0.10)
    }
}
