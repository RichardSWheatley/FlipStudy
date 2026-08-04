import XCTest
@testable import FlipStudy__Flashcards

final class CardGeneratorTests: XCTestCase {

    func test_splitsAtColonSpace_forTermDefinitionLine() {
        let cards = CardGenerator.cards(from: "Term: definition")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "Term")
        XCTAssertEqual(cards[0].back, "definition")
    }

    func test_splitsAtEmDash_forVocabularyPair() {
        let cards = CardGenerator.cards(from: "water — acqua")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "water")
        XCTAssertEqual(cards[0].back, "acqua")
    }

    func test_splitsAtTab_forTabSeparatedLine() {
        let cards = CardGenerator.cards(from: "mitochondria\tpowerhouse of the cell")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "mitochondria")
        XCTAssertEqual(cards[0].back, "powerhouse of the cell")
    }

    func test_makesFrontOnlyCard_whenLineHasNoSeparator() {
        let cards = CardGenerator.cards(from: "photosynthesis")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "photosynthesis")
        XCTAssertEqual(cards[0].back, "")
    }

    func test_dropsLine_whenShorterThanThreeCharacters() {
        let cards = CardGenerator.cards(from: "ab\ncat: feline\nx")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "cat")
        XCTAssertEqual(cards[0].back, "feline")
    }

    func test_trimsLeadingAndTrailingWhitespace_aroundLineAndAroundSeparator() {
        let cards = CardGenerator.cards(from: "   sun: star   ")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "sun")
        XCTAssertEqual(cards[0].back, "star")
    }

    func test_fallsThroughToWholeLineFront_whenTextBeforeSeparatorIsEmpty() {
        let cards = CardGenerator.cards(from: ": just back")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, ": just back")
        XCTAssertEqual(cards[0].back, "")
    }

    // "6:33" has a colon but not the ": " separator, so it survives as a
    // front-only card — this is why scanned status-bar clock text used to
    // show up as junk cards.
    func test_staysFrontOnly_whenColonHasNoTrailingSpace() {
        let cards = CardGenerator.cards(from: "6:33")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "6:33")
        XCTAssertEqual(cards[0].back, "")
    }

    func test_stripsLeadingBullet_beforeSplitting() {
        let cards = CardGenerator.cards(from: "* Good Morning - Buongiorno")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "Good Morning")
        XCTAssertEqual(cards[0].back, "Buongiorno")
    }

    func test_keepsHyphenatedWords_whenBulletStripRequiresTrailingSpace() {
        let cards = CardGenerator.cards(from: "-in-law: suocera")

        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards[0].front, "-in-law")
        XCTAssertEqual(cards[0].back, "suocera")
    }
}
