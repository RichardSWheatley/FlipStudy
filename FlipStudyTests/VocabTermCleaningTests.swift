import XCTest
@testable import FlipStudy__Flashcards

/// Pins down `tidyTerm`, the deterministic guard on the AI's vocab output,
/// born from the "scanned a screenshot of a Gemini chat" bug: OCR of the chat
/// UI produced junk cards — "- supermnercalu" bullet and all, clock times,
/// lone "O"s. The model is asked to drop that junk; this guard means one
/// slipped item still can't become a card.
final class VocabTermCleaningTests: XCTestCase {

    // MARK: - tidyTerm

    func test_tidyTerm_stripsLeadingNumbering() {
        XCTAssertEqual(AICardGenerator.tidyTerm("1. water"), "water")
        XCTAssertEqual(AICardGenerator.tidyTerm("2) tree"), "tree")
        XCTAssertEqual(AICardGenerator.tidyTerm("10 house"), "house")
    }

    func test_tidyTerm_stripsLeadingBulletPunctuation() {
        XCTAssertEqual(AICardGenerator.tidyTerm("- casa"), "casa")
        XCTAssertEqual(AICardGenerator.tidyTerm("• hola"), "hola")
        XCTAssertEqual(AICardGenerator.tidyTerm("‹ Jira"), "Jira")
    }

    func test_tidyTerm_rejectsClockTimes() {
        XCTAssertNil(AICardGenerator.tidyTerm("6:33"))
        XCTAssertNil(AICardGenerator.tidyTerm("9:49"))
        XCTAssertNil(AICardGenerator.tidyTerm("9:49 4"))
    }

    func test_tidyTerm_rejectsPureNumbers() {
        XCTAssertNil(AICardGenerator.tidyTerm("100"))
        XCTAssertNil(AICardGenerator.tidyTerm("7"))
        XCTAssertNil(AICardGenerator.tidyTerm("* 100"))
    }

    func test_tidyTerm_rejectsSingleCharacters() {
        XCTAssertNil(AICardGenerator.tidyTerm("O"))
        XCTAssertNil(AICardGenerator.tidyTerm("x"))
    }

    func test_tidyTerm_rejectsStringsEmptyAfterCleaning() {
        XCTAssertNil(AICardGenerator.tidyTerm(""))
        XCTAssertNil(AICardGenerator.tidyTerm("   "))
        XCTAssertNil(AICardGenerator.tidyTerm("•"))
        XCTAssertNil(AICardGenerator.tidyTerm("- "))
        XCTAssertNil(AICardGenerator.tidyTerm("="))
    }

    func test_tidyTerm_keepsNormalWordsAndMultiwordPhrases() {
        XCTAssertEqual(AICardGenerator.tidyTerm("water"), "water")
        XCTAssertEqual(AICardGenerator.tidyTerm("train station"), "train station")
        XCTAssertEqual(AICardGenerator.tidyTerm("  Good evening  "), "Good evening")
    }

}
