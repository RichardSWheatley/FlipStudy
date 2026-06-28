import Foundation
import SwiftData

@Model
final class Card {
    var id: UUID
    var front: String
    var back: String
    var leitnerBox: Int
    var lastReviewed: Date?
    var nextDue: Date?

    var deck: Deck?

    init(front: String, back: String, leitnerBox: Int = 1) {
        self.id = UUID()
        self.front = front
        self.back = back
        self.leitnerBox = leitnerBox
    }
}

extension Card {
    static let maxBox = 5
    /// Days a card waits in each Leitner box (index 0 == box 1).
    static let boxIntervalsDays = [1, 2, 4, 7, 14]

    func intervalDays(for box: Int) -> Int {
        let clamped = min(max(box, 1), Card.maxBox)
        return Card.boxIntervalsDays[clamped - 1]
    }

    /// Knew it: promote one box and schedule the longer interval.
    func markCorrect(now: Date = .now) {
        leitnerBox = min(leitnerBox + 1, Card.maxBox)
        lastReviewed = now
        nextDue = Calendar.current.date(byAdding: .day, value: intervalDays(for: leitnerBox), to: now)
    }

    /// Missed it: demote to box 1 so it comes back soon.
    func markIncorrect(now: Date = .now) {
        leitnerBox = 1
        lastReviewed = now
        nextDue = Calendar.current.date(byAdding: .day, value: intervalDays(for: leitnerBox), to: now)
    }

    var isDue: Bool {
        guard let nextDue else { return true }
        return nextDue <= .now
    }
}
