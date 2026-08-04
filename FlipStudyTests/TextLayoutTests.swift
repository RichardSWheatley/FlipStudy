import XCTest
import CoreGraphics
@testable import FlipStudy__Flashcards

/// Pins the reading-order rebuild. Vision reports one observation per *visual*
/// line, so a wrapped question arrives as fragments; joining them back is the
/// single biggest lever on scanned-card quality. The hard part is doing it
/// without gluing a vocabulary list into one blob — these tests hold both ends.
final class TextLayoutTests: XCTestCase {

    /// A line on a synthetic page. `row` counts down from the top; `width` is
    /// how far across the body it runs (0.8 = to the right margin).
    /// Vision's Y grows upward, so row 0 sits highest.
    private func line(_ text: String, row: Int, width: CGFloat = 0.8) -> RecognizedLine {
        let height: CGFloat = 0.04
        let pitch: CGFloat = 0.05
        let top = 0.95 - CGFloat(row) * pitch
        return RecognizedLine(text: text,
                              box: CGRect(x: 0.1, y: top - height, width: width, height: height))
    }

    func test_joinsWrappedSentence_intoOneBlock() {
        let blocks = TextLayout.blocks(from: [
            line("4. In biomechanics, what does the term \"center of", row: 0),
            line("gravity\" refer to?", row: 1, width: 0.3),
        ])

        XCTAssertEqual(blocks, [
            "4. In biomechanics, what does the term \"center of gravity\" refer to?"
        ])
    }

    func test_keepsVocabularyEntriesSeparate() {
        // Every entry stops well short of the margin, which is what marks it as
        // a deliberate line break rather than a wrap.
        let blocks = TextLayout.blocks(from: [
            line("Good Morning - Buongiorno", row: 0, width: 0.35),
            line("Thank you - Grazie", row: 1, width: 0.28),
            line("Goodbye - Arrivederci", row: 2, width: 0.31),
        ])

        XCTAssertEqual(blocks, [
            "Good Morning - Buongiorno",
            "Thank you - Grazie",
            "Goodbye - Arrivederci",
        ])
    }

    func test_terminalPunctuationEndsTheBlock_evenAtTheMargin() {
        let blocks = TextLayout.blocks(from: [
            line("The cell is the basic unit of life.", row: 0),
            line("Mitochondria produce energy for the cell.", row: 1),
        ])

        XCTAssertEqual(blocks.count, 2)
    }

    func test_paragraphGapStartsANewBlock() {
        // Row 3 leaves a blank line's worth of space — a new paragraph, not a wrap.
        let blocks = TextLayout.blocks(from: [
            line("a long line of body text that reaches the margin", row: 0),
            line("and its continuation", row: 3, width: 0.25),
        ])

        XCTAssertEqual(blocks, [
            "a long line of body text that reaches the margin",
            "and its continuation",
        ])
    }

    func test_readsTopToBottom_regardlessOfObservationOrder() {
        let blocks = TextLayout.blocks(from: [
            line("third", row: 2, width: 0.2),
            line("first", row: 0, width: 0.2),
            line("second", row: 1, width: 0.2),
        ])

        XCTAssertEqual(blocks, ["first", "second", "third"])
    }

    func test_mixedPage_joinsTheQuestionButNotTheChoices() {
        let blocks = TextLayout.blocks(from: [
            line("1. Which of the following is a key component of", row: 0),
            line("developing a physically educated individual?", row: 1, width: 0.4),
            line("A) Ability to participate in a single sport", row: 2, width: 0.45),
            line("B) Competence in motor skills", row: 3, width: 0.35),
        ])

        XCTAssertEqual(blocks, [
            "1. Which of the following is a key component of developing a physically educated individual?",
            "A) Ability to participate in a single sport",
            "B) Competence in motor skills",
        ])
    }

    func test_emptyInput_returnsNoBlocks() {
        XCTAssertEqual(TextLayout.blocks(from: []), [])
    }

    func test_singleLine_passesThroughUnchanged() {
        XCTAssertEqual(TextLayout.blocks(from: [line("Basketball", row: 0, width: 0.2)]),
                       ["Basketball"])
    }
}
