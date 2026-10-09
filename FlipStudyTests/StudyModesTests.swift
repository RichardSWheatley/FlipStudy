import XCTest
@testable import FlipStudy__Flashcards

/// Typed answers must forgive phone typing without accepting a different
/// word, and quiz choices and matching rounds must never offer two answers
/// that read the same.
final class StudyModesTests: XCTestCase {

    /// Same numbers every run, so a shuffle can't make a test flaky.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Typed answers

    func test_grade_ignoresCaseAccentsAndPunctuation() {
        XCTAssertEqual(AnswerCheck.grade(typed: "cafe", expected: "Café!"), .correct)
        XCTAssertEqual(AnswerCheck.grade(typed: "  WATER ", expected: "water"), .correct)
    }

    func test_grade_forgivesOneSlipInALongerWord() {
        XCTAssertEqual(AnswerCheck.grade(typed: "photosynthsis", expected: "photosynthesis"), .close)
        XCTAssertTrue(AnswerCheck.grade(typed: "watr", expected: "water").isRight)
    }

    func test_grade_neverForgivesAShortDifferentWord() {
        XCTAssertEqual(AnswerCheck.grade(typed: "car", expected: "cat"), .wrong)
    }

    func test_grade_doesNotAcceptAFragment() {
        // The speech grader's "contains" leniency would pass this; typing must not.
        XCTAssertEqual(AnswerCheck.grade(typed: "a", expected: "water"), .wrong)
        XCTAssertEqual(AnswerCheck.grade(typed: "wat", expected: "water"), .wrong)
    }

    func test_grade_acceptsAnyListedAlternative() {
        XCTAssertEqual(AnswerCheck.grade(typed: "large", expected: "big, large"), .correct)
        XCTAssertEqual(AnswerCheck.grade(typed: "color", expected: "colour / color"), .correct)
        XCTAssertEqual(AnswerCheck.grade(typed: "big, large", expected: "big, large"), .correct)
    }

    func test_grade_ignoresBracketedNotesAndLeadingArticles() {
        XCTAssertEqual(AnswerCheck.grade(typed: "gato", expected: "gato (m.)"), .correct)
        XCTAssertEqual(AnswerCheck.grade(typed: "eat", expected: "to eat"), .correct)
        XCTAssertEqual(AnswerCheck.grade(typed: "the dog", expected: "dog"), .correct)
    }

    func test_grade_emptyAnswerIsWrong() {
        XCTAssertEqual(AnswerCheck.grade(typed: "   ", expected: "water"), .wrong)
    }

    @MainActor
    func test_speechSimilarity_unchangedByTheSharedHelpers() {
        XCTAssertEqual(SpeechRecognizer.similarity(spoken: "the water", expected: "Water"), 1)
        XCTAssertEqual(SpeechRecognizer.similarity(spoken: "", expected: "water"), 0)
    }

    // MARK: - Quiz choices

    func test_choices_includeTheAnswerOnceAndNoLookalikes() {
        var rng = SeededGenerator(state: 1)
        let backs = ["Water", "water", "Salt", "Sugar", "Oxygen", "WATER!", "Iron"]
        for _ in 0..<50 {
            let options = QuizBuilder.choices(answer: "Water", from: backs, using: &rng)
            XCTAssertEqual(options.count, 4)
            let folded = options.map(AnswerCheck.fold)
            XCTAssertEqual(Set(folded).count, 4, "\(options)")
            XCTAssertEqual(folded.filter { $0 == "water" }.count, 1)
        }
    }

    func test_choices_shrinkWhenTheDeckIsSmall() {
        var rng = SeededGenerator(state: 2)
        let options = QuizBuilder.choices(answer: "Salt", from: ["Salt", "Sugar", "Iron"], using: &rng)
        XCTAssertEqual(Set(options), ["Salt", "Sugar", "Iron"])
    }

    func test_choices_preferSimilarLengths() {
        var rng = SeededGenerator(state: 3)
        // Six short ones fill the pool of nearest candidates for four choices.
        let backs = ["cat", "dog", "owl", "elk", "pig", "hen", "a very long answer that stands out",
                     "another long answer nobody would pick", "a third long answer here"]
        for _ in 0..<20 {
            let options = QuizBuilder.choices(answer: "cow", from: backs, using: &rng)
            XCTAssertTrue(options.allSatisfy { $0.count == 3 }, "\(options)")
        }
    }

    func test_canQuiz_needsThreeDifferentBacks() {
        XCTAssertFalse(QuizBuilder.canQuiz(backs: ["a", "A", "b"]))
        XCTAssertTrue(QuizBuilder.canQuiz(backs: ["a", "b", "c"]))
    }

    // MARK: - Matching rounds

    private func pair(_ front: String, _ back: String) -> QuizBuilder.MatchPair {
        .init(id: UUID(), front: front, back: back)
    }

    func test_matchRound_capsTheSizeAndDropsAmbiguousPairs() {
        var rng = SeededGenerator(state: 4)
        let pairs = (1...10).map { pair("front \($0)", "back \($0)") }
            + [pair("FRONT 1", "unique"), pair("unique front", "Back 2")]
        for _ in 0..<20 {
            let round = QuizBuilder.matchRound(from: pairs, using: &rng)
            XCTAssertEqual(round.count, 6)
            XCTAssertEqual(Set(round.map { AnswerCheck.fold($0.front) }).count, 6)
            XCTAssertEqual(Set(round.map { AnswerCheck.fold($0.back) }).count, 6)
        }
    }

    func test_canMatch_needsThreeDistinctPairs() {
        XCTAssertFalse(QuizBuilder.canMatch([pair("a", "1"), pair("b", "1"), pair("c", "2")]))
        XCTAssertTrue(QuizBuilder.canMatch([pair("a", "1"), pair("b", "2"), pair("c", "3")]))
    }
}
