import XCTest
@testable import FlipStudy__Flashcards

final class DeckTransferTests: XCTestCase {

    // MARK: - Round-trip

    func test_encodeThenDecode_preservesEveryField() throws {
        let original = SharedDeck(formatVersion: DeckTransfer.currentVersion,
                                  title: "Italian Vocab",
                                  subject: "Languages",
                                  cards: [SharedCard(front: "cat", back: "gatto"),
                                          SharedCard(front: "dog", back: "cane")])

        let decoded = try DeckTransfer.decode(DeckTransfer.encode(original))

        XCTAssertEqual(decoded.formatVersion, original.formatVersion)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.subject, original.subject)
        XCTAssertEqual(decoded.cards.count, original.cards.count)
        for (decodedCard, originalCard) in zip(decoded.cards, original.cards) {
            XCTAssertEqual(decodedCard.front, originalCard.front)
            XCTAssertEqual(decodedCard.back, originalCard.back)
        }
    }

    func test_encodeThenDecode_preservesEmptyCardList() throws {
        let original = SharedDeck(formatVersion: DeckTransfer.currentVersion,
                                  title: "Empty",
                                  subject: "",
                                  cards: [])

        let decoded = try DeckTransfer.decode(DeckTransfer.encode(original))

        XCTAssertEqual(decoded.title, "Empty")
        XCTAssertEqual(decoded.subject, "")
        XCTAssertTrue(decoded.cards.isEmpty)
    }

    // MARK: - Rejecting non-deck data

    func test_decode_throwsNotADeck_forNonJSONData() {
        let garbage = Data("this is not json at all".utf8)

        XCTAssertThrowsError(try DeckTransfer.decode(garbage)) { error in
            guard case DeckTransfer.TransferError.notADeck = error else {
                return XCTFail("Expected .notADeck, got \(error)")
            }
        }
    }

    func test_decode_throwsNotADeck_forValidJSONThatIsNotADeck() {
        let json = Data(#"{"recipe": "carbonara", "servings": 4}"#.utf8)

        XCTAssertThrowsError(try DeckTransfer.decode(json)) { error in
            guard case DeckTransfer.TransferError.notADeck = error else {
                return XCTFail("Expected .notADeck, got \(error)")
            }
        }
    }

    // MARK: - Format versioning

    func test_decode_throwsTooNew_forFileFromNewerAppVersion() throws {
        let futureDeck = SharedDeck(formatVersion: DeckTransfer.currentVersion + 1,
                                    title: "From the future",
                                    subject: "Time travel",
                                    cards: [])
        let data = try DeckTransfer.encode(futureDeck)

        XCTAssertThrowsError(try DeckTransfer.decode(data)) { error in
            guard case DeckTransfer.TransferError.tooNew = error else {
                return XCTFail("Expected .tooNew, got \(error)")
            }
        }
    }

    func test_decode_accepts_currentFormatVersion() throws {
        let deck = SharedDeck(formatVersion: DeckTransfer.currentVersion,
                              title: "Now",
                              subject: "Today",
                              cards: [SharedCard(front: "a", back: "b")])

        let decoded = try DeckTransfer.decode(DeckTransfer.encode(deck))

        XCTAssertEqual(decoded.formatVersion, DeckTransfer.currentVersion)
    }

    func test_decode_accepts_olderFormatVersion() throws {
        // A file written before the version field was ever bumped must still open.
        let oldDeck = SharedDeck(formatVersion: DeckTransfer.currentVersion - 1,
                                 title: "Old",
                                 subject: "History",
                                 cards: [])
        let data = try DeckTransfer.encode(oldDeck)

        XCTAssertNoThrow(try DeckTransfer.decode(data))
    }
}
