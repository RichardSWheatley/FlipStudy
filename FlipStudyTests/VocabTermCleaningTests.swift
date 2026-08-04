import XCTest
@testable import FlipStudy__Flashcards

/// Pins down the deterministic vocab-cleaning layer that guards against the
/// "scanned a screenshot of a Gemini chat" bug: OCR of the chat UI produced
/// junk cards — "- supermnercalu" bullet and all, clock times, lone "O"s.
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

    // MARK: - vocabItems

    // Real OCR output captured from the bug report: a screenshot of a Gemini
    // chat, status bar and app chrome included.
    private let geminiChatOCR = """
        9:49 4
        * 100
        ‹ Jira
        =
        Flash Extended v
        ••.
        O
        O
        O
        Basketball
        Busy
        Chicken
        Doctor
        Every day
        Exit
        Good evening
        - supermnercalu
        1. Ask Gemini
        """

    func test_vocabItems_realVocabularySurvivesInOrder_fromGeminiScreenshot() {
        let items = PhotoDeckView.vocabItems(from: geminiChatOCR)
        let vocabulary = [
            "Basketball", "Busy", "Chicken", "Doctor",
            "Every day", "Exit", "Good evening",
        ]
        XCTAssertEqual(items.filter { vocabulary.contains($0) }, vocabulary)
    }

    func test_vocabItems_dropsNoLetterLines_andCleansBulletsAndNumbering() {
        // Letter-bearing chrome ("Jira", "Flash Extended v", "Ask Gemini")
        // survives ON PURPOSE: only the AI layer can tell UI chrome from real
        // vocabulary, and any deterministic heuristic sharp enough to drop it
        // would also eat real words. If these lines vanish from the output,
        // update the code's contract deliberately — don't quietly shrink this
        // expectation to make the test pass.
        XCTAssertEqual(PhotoDeckView.vocabItems(from: geminiChatOCR), [
            "Jira",
            "Flash Extended v",
            "Basketball",
            "Busy",
            "Chicken",
            "Doctor",
            "Every day",
            "Exit",
            "Good evening",
            "supermnercalu",
            "Ask Gemini",
        ])
    }

    func test_vocabItems_dedupesCaseInsensitively_keepingFirstSpelling() {
        let items = PhotoDeckView.vocabItems(from: "Chicken\nchicken\nCHICKEN\nBusy")
        XCTAssertEqual(items, ["Chicken", "Busy"])
    }
}
