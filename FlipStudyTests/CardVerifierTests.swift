import XCTest
@testable import FlipStudy__Flashcards

/// The verify pass exists because bad cards used to reach the phone silently.
/// Each test here is a failure that actually happened during development.
final class CardVerifierTests: XCTestCase {

    private func issues(_ cards: [(front: String, back: String)],
                        target: AnswerLanguage? = nil) -> [[CardIssue]] {
        CardVerifier.check(cards, expectedBackLanguage: target).map(\.issues)
    }

    func test_cleanCards_haveNoIssues() {
        let checked = CardVerifier.check([
            (front: "What is the center of gravity?",
             back: "The point where an object's weight is evenly distributed."),
        ])

        XCTAssertEqual(checked.count, 1)
        XCTAssertFalse(checked[0].isSuspect)
    }

    func test_flagsEmptyBack() {
        XCTAssertEqual(issues([(front: "Basketball", back: "")]), [[.emptyBack]])
    }

    func test_flagsSameTextOnBothSides_ignoringCaseAndAccents() {
        // The vocabulary path seeds back == front before translation runs; if
        // translation fails the card arrives like this.
        XCTAssertEqual(issues([(front: "Buongiorno", back: "buongiorno")]),
                       [[.sameOnBothSides]])
    }

    func test_flagsDuplicateFront_onTheSecondOccurrenceOnly() {
        let result = issues([
            (front: "water", back: "acqua"),
            (front: "Water", back: "acqua"),
        ])

        XCTAssertEqual(result[0], [])
        XCTAssertEqual(result[1], [.duplicate])
    }

    func test_flagsBackThatWasNeverTranslated() {
        // Expected Italian, got English — the silent translation failure.
        let result = issues([(front: "Good morning", back: "Good morning everyone")],
                            target: .italian)

        XCTAssertTrue(result[0].contains(.notTranslated))
    }

    func test_doesNotFlagAProperTranslation() {
        let result = issues([
            (front: "Where is the bathroom?", back: "Dov'\u{00E8} il bagno?"),
        ], target: .italian)

        XCTAssertFalse(result[0].contains(.notTranslated))
    }

    func test_doesNotCheckTranslation_whenDeckStaysEnglish() {
        let result = issues([(front: "What is H2O?", back: "Water")], target: .english)

        XCTAssertFalse(result[0].contains(.notTranslated))
    }

    // MARK: - Truncation

    func test_flagsCardCutOffOnADanglingWord() {
        // Exactly the shape a wrapped line produced before the layout fix.
        XCTAssertTrue(CardVerifier.looksTruncated("In biomechanics, what does the term center of"))
        XCTAssertTrue(CardVerifier.looksTruncated("The mitochondria are the"))
    }

    func test_flagsCardEndingOnAComma_orUnbalancedBracketOrQuote() {
        XCTAssertTrue(CardVerifier.looksTruncated("First, the cell divides,"))
        XCTAssertTrue(CardVerifier.looksTruncated("Define (in your own words"))
        XCTAssertTrue(CardVerifier.looksTruncated("What does \"center of gravity mean?"))
    }

    func test_doesNotFlagCompleteText() {
        XCTAssertFalse(CardVerifier.looksTruncated("What is the center of gravity?"))
        XCTAssertFalse(CardVerifier.looksTruncated("Buongiorno"))
        XCTAssertFalse(CardVerifier.looksTruncated("The point where weight is evenly distributed."))
        XCTAssertFalse(CardVerifier.looksTruncated("What does \"center of gravity\" mean?"))
    }

    func test_emptyTextIsNotTruncated() {
        XCTAssertFalse(CardVerifier.looksTruncated(""))
        XCTAssertFalse(CardVerifier.looksTruncated("   "))
    }

    func test_flagsAParagraphUsedAsACardFront() {
        let paragraph = String(repeating: "This is a long sentence of body text. ", count: 8)
        XCTAssertTrue(issues([(front: paragraph, back: "Something")])[0]
            .contains(.tooLongForAPrompt))
    }

    func test_reportsEveryIssueOnOneCard() {
        // Empty back AND cut off: the user should see both reasons.
        let result = issues([(front: "The cell is made of the", back: "")])

        XCTAssertTrue(result[0].contains(.emptyBack))
        XCTAssertTrue(result[0].contains(.looksTruncated))
    }

    func test_everyIssueHasAUserFacingLabel() {
        for issue in CardIssue.allCases {
            XCTAssertFalse(issue.label.isEmpty, "\(issue) needs a label")
        }
    }
}
