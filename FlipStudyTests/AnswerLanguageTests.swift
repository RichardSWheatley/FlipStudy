import XCTest
@testable import FlipStudy__Flashcards

final class AnswerLanguageTests: XCTestCase {

    // MARK: - BCP-47 codes

    func test_code_matchesBCP47_forEveryCase() {
        XCTAssertEqual(AnswerLanguage.english.code, "en")
        XCTAssertEqual(AnswerLanguage.italian.code, "it")
        XCTAssertEqual(AnswerLanguage.spanish.code, "es")
        XCTAssertEqual(AnswerLanguage.french.code, "fr")
        XCTAssertEqual(AnswerLanguage.german.code, "de")
        XCTAssertEqual(AnswerLanguage.portuguese.code, "pt")
        XCTAssertEqual(AnswerLanguage.japanese.code, "ja")
        XCTAssertEqual(AnswerLanguage.chinese.code, "zh")
    }

    // MARK: - isTranslation

    func test_isTranslation_isFalseOnlyForEnglish() {
        for language in AnswerLanguage.allCases {
            XCTAssertEqual(language.isTranslation, language != .english,
                           "\(language) has wrong isTranslation")
        }
    }

    // MARK: - named(in:) title inference

    func test_named_findsLanguageMentionedInTitle() {
        XCTAssertEqual(AnswerLanguage.named(in: "Italian Vocab Week 2"), .italian)
    }

    func test_named_isCaseInsensitive() {
        XCTAssertEqual(AnswerLanguage.named(in: "SPANISH drills"), .spanish)
    }

    func test_named_returnsNil_whenNoLanguageIsMentioned() {
        XCTAssertNil(AnswerLanguage.named(in: "Vocab"))
    }

    func test_named_neverInfersEnglish() {
        // English is the no-translation default, not a target language, so a
        // title mentioning it must not flip the deck into translation mode.
        XCTAssertNil(AnswerLanguage.named(in: "English words"))
    }
}
