import Foundation
import SwiftData
import UniformTypeIdentifiers

/// A portable snapshot of a deck for sharing. This is deliberately a plain
/// `Codable` value — never the SwiftData `@Model` — so a deck can be written to
/// a small `.flipstudy` file, sent to a friend (AirDrop, Messages, Files…), and
/// added to their own decks. No accounts, no server: sharing is just a file.
struct SharedCard: Codable {
    var front: String
    var back: String
}

struct SharedDeck: Codable {
    /// Bumped if the on-disk shape ever changes, so older apps can refuse a
    /// newer file cleanly instead of decoding garbage.
    var formatVersion: Int
    var title: String
    var subject: String
    var cards: [SharedCard]
}

/// Encodes decks to shareable files and rebuilds them on the other side.
enum DeckTransfer {
    static let fileExtension = "flipstudy"
    static let currentVersion = 1

    // MARK: - Encode

    static func snapshot(of deck: Deck) -> SharedDeck {
        SharedDeck(formatVersion: currentVersion,
                   title: deck.title,
                   subject: deck.subject,
                   cards: deck.cards.map { SharedCard(front: $0.front, back: $0.back) })
    }

    static func encode(_ snapshot: SharedDeck) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    /// Write a deck to a temporary `.flipstudy` file and return its URL so a
    /// `ShareLink` can hand it to the share sheet.
    static func exportFile(for deck: Deck) throws -> URL {
        let data = try encode(snapshot(of: deck))
        let base = deck.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = sanitizedFileName(base.isEmpty ? "Deck" : base)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func sanitizedFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: illegal).joined(separator: "-")
        return cleaned.isEmpty ? "Deck" : cleaned
    }

    // MARK: - Decode

    /// Read a picked file into a snapshot, throwing a friendly error if it isn't
    /// a FlipStudy deck (wrong file, corrupt JSON, or a newer format).
    static func decode(contentsOf url: URL) throws -> SharedDeck {
        let needsStop = url.startAccessingSecurityScopedResource()
        defer { if needsStop { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> SharedDeck {
        let snapshot: SharedDeck
        do {
            snapshot = try JSONDecoder().decode(SharedDeck.self, from: data)
        } catch {
            throw TransferError.notADeck
        }
        guard snapshot.formatVersion <= currentVersion else {
            throw TransferError.tooNew
        }
        return snapshot
    }

    // MARK: - Insert

    /// Add a shared deck to the user's own decks as a brand-new deck. Nothing is
    /// merged or overwritten — importing always creates a fresh copy.
    @discardableResult
    @MainActor
    static func insert(_ snapshot: SharedDeck, into context: ModelContext) -> Deck {
        let deck = Deck(title: snapshot.title, subject: snapshot.subject, source: .shared)
        context.insert(deck)
        for shared in snapshot.cards {
            let card = Card(front: shared.front, back: shared.back)
            card.deck = deck
            context.insert(card)
        }
        return deck
    }

    enum TransferError: LocalizedError {
        case notADeck
        case tooNew

        var errorDescription: String? {
            switch self {
            case .notADeck:
                return "That file isn't a FlipStudy deck."
            case .tooNew:
                return "This deck was made with a newer version of FlipStudy. Update the app to add it."
            }
        }
    }
}
