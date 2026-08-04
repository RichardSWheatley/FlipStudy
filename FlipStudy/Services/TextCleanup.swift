import Foundation

/// Shared edge-cleaning for scanned text.
///
/// Pages decorate their content, and OCR adds its own noise on top. Italian
/// material quotes with guillemets (`«Io»`), which Vision frequently reads as
/// `<<Io`; textbooks use curly quotes. None of that is part of a card, but it
/// survived into fronts like `<<Io` because each parser cleaned edges its own
/// way. All three now share this one definition of decoration.
enum TextCleanup {
    /// Quote-like characters that mean nothing on the edge of a card. Hyphens
    /// and dashes are deliberately absent: a leading dash is handled as a list
    /// bullet only when followed by a space, so words that genuinely start with
    /// one (`-in-law`) survive.
    private static let edgeQuotes = CharacterSet(charactersIn: "«»‹›<>\"'“”„‟‚‘’")

    /// Strip quote decoration from both ends, leaving inner punctuation alone.
    /// Trimming both ends together means a properly quoted term (`"Hello"`)
    /// comes out clean rather than unbalanced.
    static func stripEdgeQuotes(_ text: String) -> String {
        text.trimmingCharacters(in: edgeQuotes)
            .trimmingCharacters(in: .whitespaces)
    }
}
