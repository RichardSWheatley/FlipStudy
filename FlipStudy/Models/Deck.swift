import Foundation
import SwiftData

enum DeckSource: String, Codable, CaseIterable {
    case manual
    case typedSubject
    case book
    case photo
    case shared

    var label: String {
        switch self {
        case .manual: "Manual"
        case .typedSubject: "Subject"
        case .book: "Book"
        case .photo: "Photo"
        case .shared: "Shared"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "square.and.pencil"
        case .typedSubject: "text.book.closed"
        case .book: "books.vertical"
        case .photo: "camera"
        case .shared: "square.and.arrow.down"
        }
    }
}

// Every stored property has a default, and `cards` is optional: iCloud sync
// (CloudKit) refuses models without both. Views read `allCards`.
@Model
final class Deck {
    var id: UUID = UUID()
    var title: String = ""
    var subject: String = ""
    var createdAt: Date = Date.now
    var source: DeckSource = DeckSource.manual

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]? = []

    init(
        title: String,
        subject: String = "",
        source: DeckSource = .manual,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.title = title
        self.subject = subject
        self.source = source
        self.createdAt = createdAt
        self.cards = []
    }

    /// The deck's cards, or none while a synced deck's cards are still arriving.
    var allCards: [Card] { cards ?? [] }

    var dueCount: Int {
        allCards.filter(\.isDue).count
    }
}
