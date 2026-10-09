import XCTest
import SwiftData
@testable import FlipStudy__Flashcards

/// Turning on iCloud sync reshaped the store: `cards` became optional, every
/// property gained a default, and settings moved to a store of their own.
/// Everyone updating already has decks in the old shape, so this builds a store
/// exactly as the last pre-sync release wrote it and checks nothing is lost.
@MainActor
final class PersistenceMigrationTests: XCTestCase {

    /// The models as the last release without sync declared them.
    enum PreSyncSchema: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)
        static var models: [any PersistentModel.Type] { [Deck.self, Card.self, AppSettings.self, StudyDay.self] }

        @Model final class Deck {
            var id: UUID
            var title: String
            var subject: String
            var createdAt: Date
            var source: DeckSource
            @Relationship(deleteRule: .cascade, inverse: \Card.deck)
            var cards: [Card]
            init(title: String) {
                id = UUID(); self.title = title; subject = ""; createdAt = .now; source = .manual; cards = []
            }
        }

        @Model final class Card {
            var id: UUID
            var front: String
            var back: String
            var leitnerBox: Int
            var lastReviewed: Date?
            var nextDue: Date?
            var deck: Deck?
            init(front: String, back: String) {
                id = UUID(); self.front = front; self.back = back; leitnerBox = 1
            }
        }

        @Model final class AppSettings {
            var cloudAIEnabled: Bool
            var translationProviderRaw: String = TranslationProvider.apple.rawValue
            var cloudTranslationRegion: String = ""
            var cloudCardsEnabled: Bool = false
            var cloudCardsLabel: String = ""
            var prefersOnDeviceCards: Bool = false
            var reminderEnabled: Bool = false
            var reminderMinutes: Int = 17 * 60
            var dailyGoal: Int = 20
            init() { cloudAIEnabled = false }
        }

        @Model final class StudyDay {
            var day: Date = Date.distantPast
            var reviewCount: Int = 0
            init(day: Date, reviewCount: Int) { self.day = day; self.reviewCount = reviewCount }
        }
    }

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Write a store the way the old app did: one store, every model, no sync.
    private func writePreSyncStore() throws {
        let schema = Schema(versionedSchema: PreSyncSchema.self)
        let config = ModelConfiguration(schema: schema, url: directory.appending(path: "default.store"),
                                        cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        let deck = PreSyncSchema.Deck(title: "Science")
        context.insert(deck)
        for (front, back) in [("H2O", "Water"), ("NaCl", "Salt")] {
            let card = PreSyncSchema.Card(front: front, back: back)
            card.deck = deck
            context.insert(card)
        }
        let settings = PreSyncSchema.AppSettings()
        settings.cloudCardsEnabled = true
        settings.cloudCardsLabel = "Family"
        settings.reminderEnabled = true
        settings.reminderMinutes = 19 * 60
        settings.dailyGoal = 35
        context.insert(settings)
        context.insert(PreSyncSchema.StudyDay(day: .now, reviewCount: 7))
        try context.save()
    }

    private func assertNothingLost(_ container: ModelContainer, file: StaticString = #filePath, line: UInt = #line) throws {
        let context = container.mainContext
        let decks = try context.fetch(FetchDescriptor<Deck>())
        XCTAssertEqual(decks.map(\.title), ["Science"], file: file, line: line)
        XCTAssertEqual(Set(decks.first?.allCards.map(\.back) ?? []), ["Water", "Salt"], file: file, line: line)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StudyDay>()).map(\.reviewCount), [7], file: file, line: line)

        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        XCTAssertEqual(settings.count, 1, file: file, line: line)
        XCTAssertEqual(settings.first?.cloudCardsEnabled, true, file: file, line: line)
        XCTAssertEqual(settings.first?.cloudCardsLabel, "Family", file: file, line: line)
        XCTAssertEqual(settings.first?.reminderEnabled, true, file: file, line: line)
        XCTAssertEqual(settings.first?.reminderMinutes, 19 * 60, file: file, line: line)
        XCTAssertEqual(settings.first?.dailyGoal, 35, file: file, line: line)
    }

    func test_updating_keepsDecksCardsStudyDaysAndSettings() throws {
        try writePreSyncStore()
        let container = Persistence.makeContainer(in: directory, allowSync: false)
        try assertNothingLost(container)
    }

    func test_updating_withSyncOn_keepsEverything() throws {
        try writePreSyncStore()
        let container = Persistence.makeContainer(in: directory, allowSync: true)
        try assertNothingLost(container)
    }

    func test_secondLaunch_keepsSettingsAndDoesNotDuplicateThem() throws {
        try writePreSyncStore()
        _ = Persistence.makeContainer(in: directory, allowSync: false)
        let again = Persistence.makeContainer(in: directory, allowSync: false)
        try assertNothingLost(again)
    }

    func test_freshInstall_startsEmpty() throws {
        let container = Persistence.makeContainer(in: directory, allowSync: false)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Deck>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<AppSettings>()), 0)
    }
}
