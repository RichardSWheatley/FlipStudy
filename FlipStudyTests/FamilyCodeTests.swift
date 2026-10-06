import XCTest
@testable import FlipStudy__Flashcards

/// The family code is the only door to FlipStudy Cloud, and it reaches the app
/// three ways: typed by hand, scanned from a QR holding the bare code, or
/// scanned from a QR holding a link. All three must normalize to the exact
/// string the Worker hashes, or a perfectly good code is rejected.
final class FamilyCodeTests: XCTestCase {

    private let canonical = "FLIPA7K29QX4"

    // MARK: - Accepting real codes

    func test_normalized_acceptsTheCodeAsPrinted() {
        XCTAssertEqual(FamilyAccess.normalized("FLIP-A7K2-9QX4"), canonical)
    }

    func test_normalized_acceptsLowercaseAndStrayWhitespace() {
        // Read aloud over the phone and typed back in, a code arrives in any case
        // and often with a trailing space from autocomplete.
        XCTAssertEqual(FamilyAccess.normalized("  flip-a7k2-9qx4 "), canonical)
        XCTAssertEqual(FamilyAccess.normalized("FLIP A7K2 9QX4"), canonical)
    }

    func test_normalized_acceptsCodeWithoutSeparators() {
        XCTAssertEqual(FamilyAccess.normalized("FLIPA7K29QX4"), canonical)
    }

    // MARK: - QR payloads

    func test_normalized_extractsCodeFromCustomSchemeLink() {
        XCTAssertEqual(FamilyAccess.normalized("flipstudy://redeem?code=FLIP-A7K2-9QX4"), canonical)
    }

    func test_normalized_extractsCodeFromHTTPSLink() {
        XCTAssertEqual(FamilyAccess.normalized("https://flipstudy.app/redeem?code=FLIP-A7K2-9QX4"),
                       canonical)
    }

    // MARK: - Rejecting junk

    func test_normalized_rejectsAnythingThatIsntAFlipStudyCode() {
        // A QR in the wild is far more likely to be a URL or a WiFi payload than
        // a family code; none of it should be sent to the Worker.
        XCTAssertNil(FamilyAccess.normalized("https://example.com"))
        XCTAssertNil(FamilyAccess.normalized(""))
        XCTAssertNil(FamilyAccess.normalized("FLIP-A7K2"))            // too short
        XCTAssertNil(FamilyAccess.normalized("FLIP-A7K2-9QX4-ZZZZ"))  // too long
        XCTAssertNil(FamilyAccess.normalized("CODE-A7K2-9QX4"))       // wrong prefix
    }

    // MARK: - Display

    func test_formatted_regroupsAScannedCodeForDisplay() {
        XCTAssertEqual(FamilyCodeView.formatted("FLIPA7K29QX4"), "FLIP-A7K2-9QX4")
        XCTAssertEqual(FamilyCodeView.formatted("flipstudy://redeem?code=FLIPA7K29QX4"),
                       "FLIP-A7K2-9QX4")
    }

    func test_formatted_leavesUnrecognizedPayloadsAlone() {
        // Shown back to the user as-is, so they can see what was actually scanned.
        XCTAssertEqual(FamilyCodeView.formatted("not a code"), "not a code")
    }

    // MARK: - Engine selection

    func test_engineStaysOnDevice_whenNoCodeIsRedeemed() {
        let settings = AppSettings()
        XCTAssertFalse(CardEngine.cloudUnlocked(settings))
        XCTAssertEqual(CardEngine.active(for: settings), .onDevice)
    }

    func test_engineStaysOnDevice_whenTheUserAsksToStayOnDevice() {
        // A privacy choice, so it outranks the cloud being available.
        let settings = AppSettings(cloudCardsEnabled: true, prefersOnDeviceCards: true)
        XCTAssertEqual(CardEngine.active(for: settings), .onDevice)
    }

    /// Without a code the scan path must behave exactly as 1.5 shipped: a page
    /// that pairs each term with its translation is split deterministically and
    /// used as-is, with no model and no network anywhere in reach.
    func test_onDeviceEngine_usesThePagesOwnPairsVerbatim() async throws {
        let page = "Italian Vocabulary\nwater - acqua\nbread - pane\ngood morning - buongiorno"
        let result = try await CardEngine.onDevice.makeVocabulary(fromText: page)

        XCTAssertTrue(result.pageSuppliedBacks)
        XCTAssertEqual(result.cards.map(\.front), ["water", "bread", "good morning"])
        XCTAssertEqual(result.cards.map(\.back), ["acqua", "pane", "buongiorno"])
    }

    func test_engineStaysOnDevice_withNoSettingsRow() {
        XCTAssertEqual(CardEngine.active(for: nil), .onDevice)
        XCTAssertFalse(CardEngine.cloudUnlocked(nil))
    }
}
