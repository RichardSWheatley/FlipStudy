import Foundation

/// Turns free-form recognized text into draft flashcards using simple,
/// deterministic rules. No network or AI required — this is the offline path.
///
/// Each non-empty line becomes one card. If a line contains a recognized
/// separator (colon, dash, en dash, em dash, pipe, or tab), the text before
/// the separator is the front and the text after is the back. Otherwise the
/// whole line is the front and the back is left blank for the user to fill in.
enum CardGenerator {
    /// Separators tried in order; the first one found in a line wins.
    private static let separators = [" — ", " – ", " - ", ": ", " | ", "\t"]

    static func cards(from text: String) -> [(front: String, back: String)] {
        text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            // A leading bullet is list decoration, not card content — without
            // this, "* Good Morning - Buongiorno" made a card whose front was
            // "* Good Morning".
            .map { $0.replacingOccurrences(of: #"^[•*·‣▪–—-]+\s+"#, with: "", options: .regularExpression) }
            .filter { $0.count >= 3 }
            .map(splitLine)
    }

    private static func splitLine(_ line: String) -> (front: String, back: String) {
        for separator in separators {
            if let range = line.range(of: separator) {
                let front = TextCleanup.stripEdgeQuotes(String(line[..<range.lowerBound]))
                let back = TextCleanup.stripEdgeQuotes(String(line[range.upperBound...]))
                if !front.isEmpty {
                    return (front, back)
                }
            }
        }
        return (TextCleanup.stripEdgeQuotes(line), "")
    }
}
