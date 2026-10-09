import Foundation

/// Grades a typed answer against a card's back, forgiving what people typing
/// on a phone get wrong — case, accents, punctuation, a slipped letter — but
/// not a different word.
enum AnswerCheck {
    enum Result: Equatable {
        /// Matches, give or take case, accents and punctuation.
        case correct
        /// One small slip. Counted right, but the spelling is worth showing.
        case close
        case wrong

        var isRight: Bool { self != .wrong }
    }

    static func grade(typed: String, expected: String) -> Result {
        let answer = fold(typed)
        guard !answer.isEmpty else { return .wrong }
        let typedForms: Set<String> = [answer, withoutLeadingArticle(answer)]
        let accepted = acceptedAnswers(for: expected)
        if !typedForms.isDisjoint(with: accepted) { return .correct }
        let isSlip = accepted.contains { target in
            typedForms.contains { isTypo($0, of: target) }
        }
        return isSlip ? .close : .wrong
    }

    /// Every form of the back that counts: the whole thing, each alternative
    /// when it lists several ("big, large", "colour / color"), each without
    /// notes in brackets ("gato (m.)"), and each without a leading "the",
    /// "a", "an" or "to", so "eat" answers "to eat".
    static func acceptedAnswers(for back: String) -> Set<String> {
        var raw = [back, withoutBrackets(back)]
        for whole in raw {
            let parts = whole.split(whereSeparator: { ",;/".contains($0) })
            if parts.count > 1 { raw += parts.map(String.init) }
        }
        var answers = Set<String>()
        for text in raw {
            let folded = fold(text)
            answers.insert(folded)
            answers.insert(withoutLeadingArticle(folded))
        }
        answers.remove("")
        return answers
    }

    /// About one wrong letter in five, and never on short words, where a
    /// single letter usually makes a different word ("cat" and "car").
    static func isTypo(_ answer: String, of expected: String) -> Bool {
        guard expected.count >= 4 else { return false }
        let allowed = max(1, expected.count / 5)
        return levenshtein(Array(answer), Array(expected)) <= allowed
    }

    /// Lowercased, accents dropped, punctuation removed, spaces collapsed:
    /// the form two answers are compared in.
    static func fold(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        return String(String.UnicodeScalarView(stripped))
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }

    static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private static func withoutBrackets(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
    }

    private static func withoutLeadingArticle(_ folded: String) -> String {
        for article in ["the ", "an ", "a ", "to "] where folded.hasPrefix(article) {
            return String(folded.dropFirst(article.count))
        }
        return folded
    }
}
