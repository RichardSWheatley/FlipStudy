import Foundation

/// Why a cloud request couldn't produce cards. Every case carries a message a
/// child or parent can act on: FlipStudy never invents cards to paper over a
/// failure, so this text *is* the whole outcome when something goes wrong.
enum CloudCardError: LocalizedError {
    case notRedeemed
    case invalidCode
    case deviceLimit
    case unauthorized
    case quotaExceeded
    case tooMuchText
    case offline
    case network(String)
    case server
    case empty

    /// Map the Worker's machine-readable error code onto a case.
    init(serverCode: String, status: Int) {
        switch serverCode {
        case "invalid_code": self = .invalidCode
        case "device_limit": self = .deviceLimit
        case "unauthorized": self = .unauthorized
        case "quota_exceeded": self = .quotaExceeded
        case "bad_request": self = .tooMuchText
        default: self = status == 401 ? .unauthorized : .server
        }
    }

    var errorDescription: String? {
        switch self {
        case .notRedeemed:
            return "Enter your family code in Settings to use FlipStudy Cloud."
        case .invalidCode:
            return "That code didn't work. Check it and try again, or ask whoever gave it to you for a new one."
        case .deviceLimit:
            return "This code is already used on as many devices as it allows. Ask for a new code."
        case .unauthorized:
            return "This phone's cloud access was turned off. Enter your family code again in Settings."
        case .quotaExceeded:
            return "This code has made all the cards it can for today. Try again tomorrow, or make cards on your device instead."
        case .tooMuchText:
            return "That's more text than FlipStudy Cloud reads at once. Scan fewer pages, or trim the text and redo."
        case .offline:
            return "FlipStudy Cloud needs the internet. Reconnect, or switch to on-device cards in Settings."
        case .network(let detail):
            return "Couldn't reach FlipStudy Cloud: \(detail)"
        case .server:
            return "FlipStudy Cloud had a problem making these cards. Try again in a moment."
        case .empty:
            return "The AI couldn't find anything to study in this text. Edit the text and redo, or scan a different page."
        }
    }

    /// The same failures, worded for "Explain This Card" rather than for
    /// making cards.
    var explanationMessage: String {
        switch self {
        case .quotaExceeded:
            return "This code has used all of FlipStudy Cloud it can for today. Try again tomorrow."
        case .server, .empty, .tooMuchText:
            return "FlipStudy Cloud couldn't explain this card. Try again in a moment."
        case .offline:
            return "Explaining a card needs the internet. Reconnect and try again."
        default:
            return errorDescription ?? "Something went wrong."
        }
    }
}

/// Why a card's answer is right, and a trick for remembering it.
struct CardExplanation: Equatable {
    let explanation: String
    let tip: String
}

/// Card generation through FlipStudy Cloud — the Cloudflare Worker that runs a
/// much larger model than the phone can hold. It is reachable **only** with a
/// redeemed family code; see `FamilyAccess` and `worker/README.md`.
///
/// The four entry points deliberately mirror `AICardGenerator`, so `CardEngine`
/// can swap engines without either caller knowing which one ran.
enum CloudCardGenerator {

    /// The deployed Worker.
    ///
    /// REPLACE THIS after `wrangler deploy` prints your service URL. Until it
    /// points at a real Worker, redeeming a code fails with a network error.
    static let endpoint = URL(string: "https://flipstudy-cards.richardswheatley.workers.dev")!

    // MARK: - Page scanning

    static func makeCards(fromText text: String, count: Int = 24) async throws -> [(front: String, back: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudCardError.empty }

        let response: CardsResponse = try await post(
            GenerateRequest(mode: "qa", text: trimmed, count: count)
        )
        let cards = response.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty }
        guard !cards.isEmpty else { throw CloudCardError.empty }
        return cards
    }

    /// Pull the vocabulary off a scanned page. The model returns each item with
    /// whatever translation **the page itself** gave it, or an empty back when
    /// the page is a plain word list — so one call covers both shapes and the
    /// caller doesn't have to guess which kind of page it scanned.
    static func makeVocabulary(fromText text: String, count: Int = 25) async throws -> [(front: String, back: String)] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CloudCardError.empty }

        let response: CardsResponse = try await post(
            GenerateRequest(mode: "vocab", text: trimmed, count: count)
        )

        var seen = Set<String>()
        var items: [(front: String, back: String)] = []
        for card in response.cards {
            var front = card.front.trimmingCharacters(in: .whitespacesAndNewlines)
            var back = card.back.trimmingCharacters(in: .whitespacesAndNewlines)

            // Observed slip: the model sometimes hands back a whole
            // "term - translation" line as the front with nothing on the back.
            // The page plainly paired those two, so split it here rather than
            // shipping a card with no answer on it.
            if back.isEmpty, let split = VocabPairDetector.splitPair(front) {
                front = split.front
                back = split.back
            }

            // The same deterministic guard the on-device path uses, so one
            // slipped item can't become a junk card whichever engine ran.
            guard let cleaned = AICardGenerator.tidyTerm(front),
                  seen.insert(cleaned.lowercased()).inserted else { continue }
            items.append((front: cleaned, back: back))
        }
        guard !items.isEmpty else { throw CloudCardError.empty }
        return items
    }

    // MARK: - Typed topics

    static func makeCards(topic: String, count: Int = 12) async throws -> [(front: String, back: String)] {
        let response: CardsResponse = try await post(
            GenerateRequest(mode: "topic", topic: topic, count: count)
        )
        let cards = response.cards
            .map { (front: $0.front.trimmingCharacters(in: .whitespacesAndNewlines),
                    back: $0.back.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.front.isEmpty }
        guard !cards.isEmpty else { throw CloudCardError.empty }
        return cards
    }

    static func makeConcepts(topic: String, style: DeckStyle, count: Int = 12) async throws -> [String] {
        let response: TermsResponse = try await post(
            GenerateRequest(mode: "concepts", topic: topic, style: style.rawValue, count: count)
        )

        var seen = Set<String>()
        var items: [String] = []

        // Sentence-starter decks begin from the same reliable basics as the
        // on-device path, so the two engines produce comparable decks.
        if style == .sentenceStarters {
            for starter in DeckStyle.basicStarters where seen.insert(starter.lowercased()).inserted {
                items.append(starter)
            }
        }

        for term in response.terms {
            let cleaned = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty,
                  AICardGenerator.isProbablyEnglish(cleaned),
                  style.accepts(cleaned),
                  seen.insert(cleaned.lowercased()).inserted
            else { continue }
            items.append(cleaned)
        }

        guard !items.isEmpty else { throw CloudCardError.empty }
        return items
    }

    // MARK: - Explaining a card

    /// A short explanation of why the back answers the front, and a memory
    /// trick, for a card the learner just missed. `subject` is the deck's
    /// subject or title, so "bank" in an economics deck isn't explained as a
    /// river bank. If the card itself is wrong, the explanation says so.
    static func explain(front: String, back: String, subject: String) async throws -> CardExplanation {
        let response: ExplainResponse = try await post(
            GenerateRequest(mode: "explain", topic: subject, front: front, back: back, count: 1)
        )
        let explanation = response.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanation.isEmpty else { throw CloudCardError.empty }
        return CardExplanation(explanation: explanation,
                               tip: response.tip.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Transport

    private static func post<T: Decodable>(_ body: GenerateRequest) async throws -> T {
        let token = FamilyAccess.token
        guard !token.isEmpty else { throw CloudCardError.notRedeemed }

        var request = URLRequest(url: endpoint.appending(path: "v1/generate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        // Generous: a big page through a 70B model is not instant, and a
        // spurious timeout reads to the user as the feature being broken.
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .notConnectedToInternet
                                        || error.code == .networkConnectionLost
                                        || error.code == .cannotFindHost
                                        || error.code == .cannotConnectToHost
                                        || error.code == .dnsLookupFailed {
            throw CloudCardError.offline
        } catch let error as URLError where error.code == .timedOut {
            throw CloudCardError.server
        } catch {
            throw CloudCardError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw CloudCardError.server }
        guard http.statusCode == 200 else {
            throw CloudCardError(serverCode: FamilyAccess.errorCode(in: data),
                                 status: http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CloudCardError.server
        }
    }

    private struct GenerateRequest: Encodable {
        let mode: String
        var text: String?
        var topic: String?
        var style: String?
        var front: String?
        var back: String?
        let count: Int
    }

    private struct ExplainResponse: Decodable {
        let explanation: String
        let tip: String
    }

    private struct CardsResponse: Decodable {
        let cards: [DraftCard]
    }

    private struct DraftCard: Decodable {
        let front: String
        let back: String
    }

    private struct TermsResponse: Decodable {
        let terms: [String]
    }
}
