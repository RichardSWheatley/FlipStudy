import XCTest
@testable import FlipStudy__Flashcards

/// Behavioral tests for `PhotoDeckView.detectPageKind(of:)` — the heuristic
/// that decides whether a scanned page is Q&A or a vocabulary list.
final class PageKindDetectionTests: XCTestCase {

    func test_detectsQuestions_forNumberedMultipleChoicePageWithAnswerLines() {
        let text = """
        1. What is the capital of France?
        A) London
        B) Paris
        C) Madrid
        Answer: B
        2. What is 2 + 2?
        A) 3
        B) 4
        Answer: B
        """
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: text), .questions)
    }

    func test_detectsVocabulary_forPlainWordList() {
        let text = """
        apple
        mountain
        to run
        beautiful
        the library
        yesterday
        """
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: text), .vocabulary)
    }

    func test_detectsQuestions_forProseParagraphsWithoutQuestionMarks() {
        // Long lines with no question shapes: prose reads best as Q&A
        // extraction, not as a word list.
        let text = """
        The water cycle describes how water moves between the oceans and the sky.
        Evaporation lifts moisture into the air where it cools and condenses.
        Eventually the droplets grow heavy enough to fall back down as precipitation.
        """
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: text), .questions)
    }

    func test_defaultsToQuestions_forEmptyText() {
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: ""), .questions)
    }

    func test_defaultsToQuestions_forWhitespaceOnlyText() {
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: " \n\t\n   \n"), .questions)
    }

    func test_staysVocabulary_whenWordListContainsSingleQuestionMark() {
        // One stray "?" is a single signal — below the two-signal threshold,
        // so the short-line shape still wins.
        let text = """
        el perro
        la casa
        por que?
        el gato
        la escuela
        """
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: text), .vocabulary)
    }

    func test_detectsQuestions_forChatScreenshotOCRFixture() {
        // Real OCR output from a chat-app screenshot: status-bar noise and UI
        // chrome around one Q&A pair. The "?" line plus the "Answer:" line
        // must be enough to call it a question page.
        let text = """
        6:33
        754
        =
        Flash Extended v
        •••
        Here is the list of questions and their correct answers
        from the image:
        1.
        2.
        Which of the following is a key component of
        developing a physically educated individual
        as outlined by SHAPE America standards?
        O
        Answer: C) Competence in motor skills
        and movement patterns
        """
        XCTAssertEqual(PhotoDeckView.detectPageKind(of: text), .questions)
    }
}
