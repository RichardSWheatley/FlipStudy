import Foundation
import NaturalLanguage

/// Recognizes a vocabulary page that already pairs each term with its
/// translation — the shape an AI chat or a textbook glossary produces:
///
///     * Good Morning - Buongiorno
///     * Thank you — Grazie
///
/// Those lines are finished flashcards; nothing should be generated or
/// re-translated. Detection is deterministic (no model needed) so it works on
/// every device, and the page's own translations are always kept over anything
/// an engine would produce.
enum VocabPairDetector {
    /// Separators tried in order; the first one found in a line wins. Same
    /// family as `CardGenerator`'s, plus "=" which bilingual lists often use.
    private static let separators = [" — ", " – ", " - ", " = ", ": ", " | ", "\t"]

    /// The page's lines as (front, back) pairs, or nil when this isn't a
    /// paired list. It counts as one when at least two lines split cleanly and
    /// the splits make up at least half of the useful lines — a stray dash in
    /// an ordinary word list shouldn't hijack the whole page.
    static func pairs(from text: String) -> [(front: String, back: String)]? {
        let lines = text.split(whereSeparator: \.isNewline)
            .compactMap { AICardGenerator.tidyTerm(String($0)) }
        guard !lines.isEmpty else { return nil }

        let paired = lines.compactMap(splitPair)
        guard paired.count >= 2, paired.count * 2 >= lines.count else { return nil }

        var seen = Set<String>()
        return paired.filter { seen.insert($0.front.lowercased()).inserted }
    }

    /// Split one cleaned line into a pair, requiring real words on both sides
    /// so "6:33" or a trailing dash can never masquerade as a pair.
    static func splitPair(_ line: String) -> (front: String, back: String)? {
        for separator in separators {
            guard let range = line.range(of: separator) else { continue }
            let front = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            let back = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard front.rangeOfCharacter(from: .letters) != nil,
                  back.rangeOfCharacter(from: .letters) != nil else { continue }
            return (front, back)
        }
        return nil
    }

    /// The language the backs are written in, when the detector is confident
    /// and it's one the app offers. Lets the UI show "English → Italian"
    /// instead of pretending the page needs translating.
    static func backLanguage(of pairs: [(front: String, back: String)]) -> AnswerLanguage? {
        let sample = pairs.map { $0.back }.joined(separator: " ")
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let dominant = recognizer.dominantLanguage else { return nil }
        return AnswerLanguage.allCases.first { $0.code == dominant.rawValue }
    }
}
