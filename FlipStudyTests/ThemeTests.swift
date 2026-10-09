import XCTest
@testable import FlipStudy__Flashcards

/// A deck that never chose a colour or emoji gets one picked for it. The pick
/// must be the same on every launch and every device, or decks would change
/// colour on their own; and an emoji guessed from the title must not jump at
/// word fragments.
final class ThemeTests: XCTestCase {

    func test_stableHash_isTheSameEveryTime() {
        // Pinned value: Swift's own hashValue changes per launch; this must not.
        XCTAssertEqual(stableHash("FlipStudy"), stableHash("FlipStudy"))
        XCTAssertEqual(stableHash(""), 5381)
        XCTAssertNotEqual(stableHash("a"), stableHash("b"))
    }

    func test_automaticPalette_dependsOnlyOnTheSeed() {
        let seed = "3F2504E0-4F89-11D3-9A0C-0305E82C3301"
        XCTAssertEqual(DeckPalette.automatic(for: seed), DeckPalette.automatic(for: seed))
        let spread = Set((0..<64).map { DeckPalette.automatic(for: "deck-\($0)") })
        XCTAssertGreaterThan(spread.count, 4, "colours should vary across decks")
    }

    func test_emojiGuess_matchesWholeWordsAndPlurals() {
        XCTAssertEqual(DeckEmoji.automatic(title: "Spanish Verbs", subject: "", seed: "x"), "🗣️")
        XCTAssertEqual(DeckEmoji.automatic(title: "Planets", subject: "", seed: "x"), "🚀")
        XCTAssertEqual(DeckEmoji.automatic(title: "Dinosaurs!", subject: "", seed: "x"), "🦖")
        XCTAssertEqual(DeckEmoji.automatic(title: "Week 3", subject: "Maths", seed: "x"), "🔢")
    }

    func test_emojiGuess_ignoresWordFragments() {
        // "Education" contains "cat", "Start" contains "star" and "art".
        let education = DeckEmoji.automatic(title: "Education", subject: "", seed: "e")
        XCTAssertNotEqual(education, "🐶")
        XCTAssertTrue(DeckEmoji.choices.contains(education))
        XCTAssertNotEqual(DeckEmoji.automatic(title: "Start Here", subject: "", seed: "s"), "🚀")
    }

    func test_appTheme_iconNamesMatchTheAlternateIcons() {
        XCTAssertNil(AppTheme.classic.iconName)
        XCTAssertEqual(AppTheme.bubblegum.iconName, "AppIcon-Bubblegum")
        // Every alternate icon the build ships must belong to a theme.
        let names = Set(AppTheme.allCases.compactMap(\.iconName))
        XCTAssertEqual(names.count, AppTheme.allCases.count - 1)
    }

    func test_cheer_starsAndHeadline() {
        XCTAssertEqual(Cheer.stars(correct: 10, total: 10), 3)
        XCTAssertEqual(Cheer.stars(correct: 6, total: 10), 2)
        XCTAssertEqual(Cheer.stars(correct: 1, total: 10), 1)
        XCTAssertEqual(Cheer.finish(correct: 5, total: 5).title, "Perfect!")
        XCTAssertEqual(Cheer.finish(correct: 0, total: 0).title, "All Done!")
    }
}
