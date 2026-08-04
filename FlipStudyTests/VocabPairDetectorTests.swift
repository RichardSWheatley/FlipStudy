import XCTest
@testable import FlipStudy__Flashcards

/// Pins the paired-vocabulary contract: a page that already couples each term
/// with its translation ("* Good Morning - Buongiorno") IS the deck. The
/// detector must take those pairs verbatim — no generation, no re-translation —
/// and recognize what language the backs are in.
final class VocabPairDetectorTests: XCTestCase {

    // The shape that motivated this: an AI chat asked for a vocab list makes
    // bulleted English–Italian pairs, which the scanner previously mangled
    // into blob fronts and then re-translated.
    private let bulletedItalianList = """
        * Good Morning - Buongiorno
        * Good evening - Buonasera
        * Thank you - Grazie
        * You're welcome - Prego
        * Goodbye - Arrivederci
        """

    func test_pairs_readsBulletedBilingualList_frontsAndBacksVerbatim() throws {
        let pairs = try XCTUnwrap(VocabPairDetector.pairs(from: bulletedItalianList))
        XCTAssertEqual(pairs.count, 5)
        XCTAssertEqual(pairs[0].front, "Good Morning")
        XCTAssertEqual(pairs[0].back, "Buongiorno")
        XCTAssertEqual(pairs[4].front, "Goodbye")
        XCTAssertEqual(pairs[4].back, "Arrivederci")
    }

    func test_pairs_supportsDashColonEqualsAndEmDashSeparators() throws {
        let text = """
        water — acqua
        bread – pane
        cheese = formaggio
        wine: vino
        """
        let pairs = try XCTUnwrap(VocabPairDetector.pairs(from: text))
        XCTAssertEqual(pairs.map { $0.front }, ["water", "bread", "cheese", "wine"])
        XCTAssertEqual(pairs.map { $0.back }, ["acqua", "pane", "formaggio", "vino"])
    }

    func test_pairs_survivesScreenshotChromeAroundTheList() throws {
        let text = """
        9:41
        * 100
        Good Morning - Buongiorno
        Thank you - Grazie
        O
        """
        let pairs = try XCTUnwrap(VocabPairDetector.pairs(from: text))
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs[1].front, "Thank you")
        XCTAssertEqual(pairs[1].back, "Grazie")
    }

    func test_pairs_stripsOCRQuoteDecoration_fromTheItalianList() {
        // "<<Io - I" is Vision's reading of «Io» - I. Neither the guillemet nor
        // its misread should reach a card.
        let pairs = try? XCTUnwrap(VocabPairDetector.pairs(from: """
            <<Io - I
            «Tu» - You
            Lui - He
            """))
        XCTAssertEqual(pairs?.map(\.front), ["Io", "Tu", "Lui"])
        XCTAssertEqual(pairs?.map(\.back), ["I", "You", "He"])
    }

    func test_pairs_returnsNilForPlainWordList() {
        XCTAssertNil(VocabPairDetector.pairs(from: "Basketball\nBusy\nChicken\nDoctor"))
    }

    func test_pairs_oneStrayDashDoesNotHijackAWordList() {
        // Majority rule: a single splittable line in a longer plain list must
        // not flip the whole page into "already translated" mode.
        let text = """
        Basketball
        Busy
        Chicken
        Doctor
        Every day
        check-in - registrazione
        """
        XCTAssertNil(VocabPairDetector.pairs(from: text))
    }

    func test_pairs_dedupesByFrontCaseInsensitively() throws {
        let text = """
        water - acqua
        Water - acqua
        bread - pane
        """
        let pairs = try XCTUnwrap(VocabPairDetector.pairs(from: text))
        XCTAssertEqual(pairs.map { $0.front }, ["water", "bread"])
    }

    func test_splitPair_requiresLettersOnBothSides() {
        XCTAssertNil(VocabPairDetector.splitPair("6: 33"))
        XCTAssertNil(VocabPairDetector.splitPair("total: 100"))
        XCTAssertNil(VocabPairDetector.splitPair("word -"))
        XCTAssertNotNil(VocabPairDetector.splitPair("word - parola"))
    }

    func test_backLanguage_recognizesItalianBacks() throws {
        let pairs = try XCTUnwrap(VocabPairDetector.pairs(from: bulletedItalianList))
        XCTAssertEqual(VocabPairDetector.backLanguage(of: pairs), .italian)
    }

    func test_backLanguage_nilForEmptyInput() {
        XCTAssertNil(VocabPairDetector.backLanguage(of: []))
    }

    // MARK: - OCR pre-cleaning (shown text = used text)

    func test_cleanedOCRLines_dropsNoLetterChrome_keepsWordLinesVerbatim() {
        let lines = ["9:41", "* 100", "=", "O", "* Good Morning - Buongiorno", "  Thank you  "]
        XCTAssertEqual(PhotoDeckView.cleanedOCRLines(lines),
                       ["* Good Morning - Buongiorno", "Thank you"])
    }
}
