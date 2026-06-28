import Foundation
import SwiftData

enum DeckSource: String, Codable, CaseIterable {
    case manual
    case typedSubject
    case book
    case photo

    var label: String {
        switch self {
        case .manual: "Manual"
        case .typedSubject: "Subject"
        case .book: "Book"
        case .photo: "Photo"
        }
    }

    var systemImage: String {
        switch self {
        case .manual: "square.and.pencil"
        case .typedSubject: "text.book.closed"
        case .book: "books.vertical"
        case .photo: "camera"
        }
    }
}

@Model
final class Deck {
    var id: UUID
    var title: String
    var subject: String
    var createdAt: Date
    var source: DeckSource

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]

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

    var dueCount: Int {
        cards.filter(\.isDue).count
    }
}
