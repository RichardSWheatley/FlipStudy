#if DEBUG
import Foundation
import SwiftData

/// Sample decks for screenshots and simulator checks. Launch a debug build with
/// `-demoDecks` to add them to an empty app. Never compiled into release builds.
enum DemoDecks {
    @MainActor
    static func insertIfRequested(into context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoDecks"),
              (try? context.fetchCount(FetchDescriptor<Deck>())) == 0 else { return }

        let decks: [(title: String, color: DeckPalette, emoji: String, cards: [(String, String)])] = [
            ("Spanish Animals", .berry, "🗣️", [("el perro", "the dog"), ("el gato", "the cat"), ("el pájaro", "the bird"),
                                                ("el caballo", "the horse"), ("la vaca", "the cow"), ("el pez", "the fish")]),
            ("Solar System", .grape, "🚀", [("Closest planet to the Sun", "Mercury"), ("Largest planet", "Jupiter"),
                                            ("The red planet", "Mars"), ("The planet with big rings", "Saturn"),
                                            ("The planet we live on", "Earth")]),
            ("Times Tables", .tangerine, "🔢", [("6 × 7", "42"), ("8 × 8", "64"), ("9 × 6", "54"), ("7 × 7", "49"), ("12 × 3", "36")]),
            ("Dinosaurs", .lime, "🦖", [("Three horns on its face", "Triceratops"), ("Plates along its back", "Stegosaurus"),
                                        ("Very long neck", "Brachiosaurus"), ("Huge meat-eater with tiny arms", "Tyrannosaurus rex")]),
        ]
        for (offset, demo) in decks.enumerated() {
            let deck = Deck(title: demo.title, createdAt: .now.addingTimeInterval(Double(-offset)))
            deck.colorIndex = demo.color.rawValue
            deck.emoji = demo.emoji
            context.insert(deck)
            for (front, back) in demo.cards {
                let card = Card(front: front, back: back)
                card.deck = deck
                context.insert(card)
            }
        }
        try? context.save()
    }
}
#endif
