import Foundation

/// The other ways to study a deck, beside flipping cards.
enum StudyMode: String, Identifiable, CaseIterable {
    case flashcards
    /// Type the back from memory.
    case typeAnswer
    /// Pick the back from a few choices.
    case multipleChoice
    /// Pair fronts with backs against the clock.
    case match

    var id: Self { self }
}

/// Builds multiple-choice questions and matching rounds out of a deck's own
/// cards, so they work for any deck without an AI.
enum QuizBuilder {
    /// A deck needs this many different backs for a question to have
    /// something to choose between, or for a matching round to be a game.
    static let minimumDistinct = 3

    static func canQuiz(backs: [String]) -> Bool {
        Set(backs.map(AnswerCheck.fold).filter { !$0.isEmpty }).count >= minimumDistinct
    }

    /// The right answer plus up to `count - 1` wrong ones from the deck's
    /// other backs, shuffled. No two choices read the same (ignoring case and
    /// accents), and wrong answers about as long as the right one are
    /// preferred, so the answer doesn't give itself away by its size.
    static func choices<G: RandomNumberGenerator>(
        answer: String,
        from backs: [String],
        count: Int = 4,
        using rng: inout G
    ) -> [String] {
        var seen: Set<String> = [AnswerCheck.fold(answer)]
        var wrong: [String] = []
        for back in backs {
            let key = AnswerCheck.fold(back)
            if !key.isEmpty, seen.insert(key).inserted { wrong.append(back) }
        }
        wrong.shuffle(using: &rng)
        wrong.sort { abs($0.count - answer.count) < abs($1.count - answer.count) }
        // A little randomness among the nearest, so the same card doesn't
        // always get the same three wrong answers.
        var nearest = Array(wrong.prefix(max(count - 1, 0) * 2))
        nearest.shuffle(using: &rng)
        var options = Array(nearest.prefix(max(count - 1, 0))) + [answer]
        options.shuffle(using: &rng)
        return options
    }

    struct MatchPair: Identifiable, Equatable {
        let id: UUID
        let front: String
        let back: String
    }

    static func canMatch(_ pairs: [MatchPair]) -> Bool {
        distinctPairs(pairs).count >= minimumDistinct
    }

    /// Up to `size` pairs for one round, chosen at random. Pairs whose front
    /// or back reads the same as another's are left out, so every tile has
    /// exactly one partner.
    static func matchRound<G: RandomNumberGenerator>(
        from pairs: [MatchPair],
        size: Int = 6,
        using rng: inout G
    ) -> [MatchPair] {
        var shuffled = pairs
        shuffled.shuffle(using: &rng)
        return Array(distinctPairs(shuffled).prefix(size))
    }

    private static func distinctPairs(_ pairs: [MatchPair]) -> [MatchPair] {
        var fronts = Set<String>()
        var backs = Set<String>()
        return pairs.filter { pair in
            let front = AnswerCheck.fold(pair.front)
            let back = AnswerCheck.fold(pair.back)
            guard !front.isEmpty, !back.isEmpty,
                  !fronts.contains(front), !backs.contains(back) else { return false }
            fronts.insert(front)
            backs.insert(back)
            return true
        }
    }
}
