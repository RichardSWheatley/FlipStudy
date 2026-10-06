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
    /// token is what actually works.
    static func cloudUnlocked(_ settings: AppSettings?) -> Bool {
        (settings?.cloudCardsEnabled ?? false) && FamilyAccess.isActive
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

    func makeTerms(fromText text: String) async throws -> [String] {
        switch self {
        case .onDevice: try await AICardGenerator.makeTerms(fromText: text)
        case .cloud: try await CloudCardGenerator.makeTerms(fromText: text)
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
