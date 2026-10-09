import Foundation

/// Which engine turns text into cards.
///
/// FlipStudy ships on-device only. A family code adds `.cloud` — a far larger
/// model behind a Cloudflare Worker — and *nothing else changes*: without a
/// redeemed code the app behaves exactly as it did before, Apple Intelligence
/// or a plain-language reason why not.
///
/// Both cases expose the same four entry points so callers never branch on the
/// engine, and neither engine ever falls back to the other: a failure is
/// reported, never papered over with worse cards.
enum CardEngine {
    case onDevice
    case cloud

    // MARK: - Choosing

    /// True when this phone has redeemed a family code and the stored token is
    /// still present. Both halves matter: the flag drives SwiftUI updates, the
    /// token is what actually works. Never true in the App Store build, which
    /// doesn't offer family codes at all (see `Distribution`).
    static func cloudUnlocked(_ settings: AppSettings?) -> Bool {
        Distribution.allowsFamilyCodes
            && (settings?.cloudCardsEnabled ?? false)
            && FamilyAccess.isActive
    }

    /// The engine a request should use. Cloud wins whenever it's unlocked,
    /// because that's the premium path a code buys — unless the user has asked
    /// to stay on-device, which is a privacy choice and is never overridden.
    static func active(for settings: AppSettings?) -> CardEngine {
        guard cloudUnlocked(settings),
              !(settings?.prefersOnDeviceCards ?? false)
        else { return .onDevice }
        return .cloud
    }

    /// Whether the smart features should appear in the New Deck menu at all.
    /// Hardware that can't run Apple Intelligence still qualifies once a code
    /// is redeemed — that's the whole point of the cloud engine.
    static func isOfferable(_ settings: AppSettings?) -> Bool {
        AICardGenerator.isDeviceEligible || cloudUnlocked(settings)
    }

    // MARK: - Availability

    var isAvailable: Bool {
        switch self {
        case .onDevice: AICardGenerator.isAvailable
        case .cloud: FamilyAccess.isActive
        }
    }

    /// A user-facing reason this engine can't run right now, or nil if it can.
    var unavailableReason: String? {
        switch self {
        case .onDevice:
            return AICardGenerator.unavailableReason
        case .cloud:
            return FamilyAccess.isActive ? nil : CloudCardError.notRedeemed.errorDescription
        }
    }

    // MARK: - Generation

    func makeCards(fromText text: String) async throws -> [(front: String, back: String)] {
        switch self {
        case .onDevice: try await AICardGenerator.makeCards(fromText: text)
        case .cloud: try await CloudCardGenerator.makeCards(fromText: text)
        }
    }

    /// A scanned vocabulary page's cards, plus whether the page supplied the
    /// backs itself (a term–translation list) rather than them still needing
    /// translation. Both engines answer the same question; only the cloud one
    /// reads the pairings with a model.
    func makeVocabulary(fromText text: String) async throws -> (cards: [(front: String, back: String)], pageSuppliedBacks: Bool) {
        switch self {
        case .onDevice:
            // Unchanged from 1.5. A page that already pairs each term with its
            // translation IS the deck, and a separator split reads it more
            // reliably than the small on-device model would.
            if let pairs = VocabPairDetector.pairs(from: text) {
                return (pairs, true)
            }
            // A plain list: the back carries the English term so translation
            // can fill it in afterwards.
            let items = try await AICardGenerator.makeTerms(fromText: text)
            return (items.map { (front: $0, back: $0) }, false)

        case .cloud:
            let items = try await CloudCardGenerator.makeVocabulary(fromText: text)
            // Majority rule, matching the detector: one stray splittable line in
            // a plain word list must not flip the whole page into paired mode.
            let withBacks = items.filter { !$0.back.isEmpty }.count
            guard withBacks * 2 >= items.count else {
                return (items.map { (front: $0.front, back: $0.front) }, false)
            }
            return (items, true)
        }
    }

    func makeCards(topic: String) async throws -> [(front: String, back: String)] {
        switch self {
        case .onDevice: try await AICardGenerator.makeCards(topic: topic)
        case .cloud: try await CloudCardGenerator.makeCards(topic: topic)
        }
    }

    func makeConcepts(topic: String, style: DeckStyle) async throws -> [String] {
        switch self {
        case .onDevice: try await AICardGenerator.makeConcepts(topic: topic, style: style)
        case .cloud: try await CloudCardGenerator.makeConcepts(topic: topic, style: style)
        }
    }

    // MARK: - Errors

    /// One plain-language message for a failure from either engine.
    static func friendlyMessage(for error: Error) -> String {
        if let cloudError = error as? CloudCardError {
            return cloudError.errorDescription ?? "FlipStudy Cloud couldn't make cards this time."
        }
        return AICardGenerator.friendlyMessage(for: error)
    }
}
