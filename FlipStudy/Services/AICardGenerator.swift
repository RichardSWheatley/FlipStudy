import Foundation
import FoundationModels

/// Turns a plain-language topic into draft flashcards using Apple's on-device
/// Foundation Model. Everything runs locally — no network, no API key — so it's
/// free and private, which is why it's the default (non-gated) AI path.
enum AICardGenerator {

    /// A single generated card. `@Generable` lets the model fill it directly
    /// via guided generation, so we never parse free-form text.
    @Generable
    struct DraftCard {
        @Guide(description: "A short question or term for the front of the card")
        var front: String
        @Guide(description: "A concise answer or definition for the back, one or two sentences")
        var back: String
    }

    @Generable
    struct DraftDeck {
        @Guide(description: "The flashcards for this topic")
        var cards: [DraftCard]
    }

    enum GenerationError: LocalizedError {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case empty

        var errorDescription: String? {
            switch self {
            case .deviceNotEligible:
                return "This device can't run on-device AI. You can still add cards by hand or scan a page."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to make cards with AI."
            case .modelNotReady:
                return "The AI model is still getting ready. Try again in a little while."
            case .empty:
                return "The AI didn't return any cards. Try rewording the topic."
            }
        }
    }

    /// Whether on-device generation can run right now.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// A user-facing reason the feature is unavailable, or nil if it's ready.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return GenerationError.deviceNotEligible.errorDescription
        case .unavailable(.appleIntelligenceNotEnabled):
            return GenerationError.appleIntelligenceNotEnabled.errorDescription
        case .unavailable(.modelNotReady):
            return GenerationError.modelNotReady.errorDescription
        case .unavailable:
            return GenerationError.modelNotReady.errorDescription
        }
    }

    static func makeCards(topic: String, count: Int = 12) async throws -> [(front: String, back: String)] {
        switch SystemLanguageModel.default.availability {
        case .available:
            break
        case .unavailable(.deviceNotEligible):
            throw GenerationError.deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled):
            throw GenerationError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw GenerationError.modelNotReady
        case .unavailable:
            throw GenerationError.modelNotReady
        }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = """
        Create \(count) study flashcards about: \(topic).
        Each card has a short prompt on the front and a concise answer on the \
        back. Keep them factual and suitable for a student.
        """
        let response = try await session.respond(to: prompt, generating: DraftDeck.self)

        let cards = response.content.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty }
        guard !cards.isEmpty else { throw GenerationError.empty }
        return cards
    }

    private static let instructions = """
    You are a helpful study assistant that writes clear, accurate flashcards.
    Fronts are brief terms or questions. Backs are short, correct answers or
    definitions. Avoid trick questions and keep the language age-appropriate.
    """
}
