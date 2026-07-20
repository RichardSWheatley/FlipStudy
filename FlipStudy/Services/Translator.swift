import Foundation
import Translation

/// A translation provider. Apple's on-device engine is the default; this seam
/// lets a cloud provider (Google/Microsoft REST APIs, behind the parent gate)
/// be added later without changing the UI that calls it.
protocol Translator {
    /// Translate each string, preserving order. A failed item comes back empty.
    func translate(_ texts: [String]) async throws -> [String]
}

/// The engine that turns English into the answer language. Apple's on-device
/// engine is free, private, and the default; the cloud engines call a REST API
/// with the parent's own key and are only reachable after the grown-up gate.
enum TranslationProvider: String, CaseIterable, Identifiable {
    case apple, google, microsoft

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: "Apple (on-device)"
        case .google: "Google Translate"
        case .microsoft: "Microsoft Translator"
        }
    }

    /// Cloud engines need the parent gate and an API key; Apple needs neither.
    var isCloud: Bool { self != .apple }

    /// Short note shown under the picker to explain the trade-off.
    var footnote: String {
        switch self {
        case .apple:
            "Runs on your device — free, private, no account needed."
        case .google, .microsoft:
            "Uses your own API key and sends terms to \(label) over the internet."
        }
    }
}

/// Errors from the cloud translation path, phrased for a parent to act on.
enum CloudTranslationError: LocalizedError {
    case missingKey
    case network(String)
    case badResponse
    case notEnabled

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "Add your translation API key in Settings to use this engine."
        case .network(let detail):
            return "Couldn't reach the translation service: \(detail)"
        case .badResponse:
            return "The translation service returned something unexpected. Check the API key."
        case .notEnabled:
            return "Turn on Cloud AI in Settings to use an online translation engine."
        }
    }
}

/// On-device translation using Apple's `Translation` framework. The session is
/// vended by SwiftUI's `.translationTask` modifier, so this wrapper is built
/// inside that modifier's action closure with the session it provides.
struct AppleTranslator: Translator {
    let session: TranslationSession

    func translate(_ texts: [String]) async throws -> [String] {
        guard !texts.isEmpty else { return [] }
        // On first use of a language pair the model may not be downloaded yet.
        // Preparing the session triggers the system's download flow so the
        // translation actually runs instead of failing with "unable to translate".
        try await session.prepareTranslation()

        let requests = texts.enumerated().map {
            TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
        }
        let responses = try await session.translations(from: requests)

        var byIdentifier: [String: String] = [:]
        for response in responses {
            if let id = response.clientIdentifier {
                byIdentifier[id] = response.targetText
            }
        }
        return texts.indices.map { byIdentifier[String($0)] ?? "" }
    }
}

/// The answer language for a generated deck. English means "no translation" —
/// the deck is plain question/answer cards. Any other value makes an
/// English → language vocabulary deck.
enum AnswerLanguage: String, CaseIterable, Identifiable {
    case english, italian, spanish, french, german, portuguese, japanese, chinese

    var id: String { rawValue }

    var label: String {
        switch self {
        case .english: "English"
        case .italian: "Italian"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        case .portuguese: "Portuguese"
        case .japanese: "Japanese"
        case .chinese: "Chinese"
        }
    }

    /// BCP-47 code used to build a `Locale.Language`.
    var code: String {
        switch self {
        case .english: "en"
        case .italian: "it"
        case .spanish: "es"
        case .french: "fr"
        case .german: "de"
        case .portuguese: "pt"
        case .japanese: "ja"
        case .chinese: "zh"
        }
    }

    var isTranslation: Bool { self != .english }

    var locale: Locale.Language { Locale.Language(identifier: code) }
}

/// Whether a generated deck should be single vocabulary words or full phrases.
/// The choice is explicit (a picker) rather than guessed from the topic, and it
/// is enforced by a hard word-count filter so "Phrases" never yields lone words.
enum DeckStyle: String, CaseIterable, Identifiable {
    case words, phrases, sentenceStarters

    var id: String { rawValue }

    var label: String {
        switch self {
        case .words: "Single words"
        case .phrases: "Phrases & sentences"
        case .sentenceStarters: "Sentence starters"
        }
    }

    /// True if `text` fits this style. Phrases and starters must be more than one
    /// word (a lone word can't be a sentence opener).
    func accepts(_ text: String) -> Bool {
        let wordCount = text.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        switch self {
        case .words: return wordCount >= 1
        case .phrases, .sentenceStarters: return wordCount >= 2
        }
    }

    /// A fixed set of the most common English sentence openers. These are the
    /// same for every language — they're written in English and the translator
    /// turns them into the target language — so every "sentence starters" deck
    /// begins from the same reliable basics before the AI adds more.
    static let basicStarters: [String] = [
        "I want",
        "I need",
        "I would like",
        "I have",
        "I am",
        "I don't",
        "I can",
        "I like",
        "Can you",
        "Could you",
        "Do you have",
        "Where is",
        "How much is",
        "I would like to",
        "Is there",
        "There is",
        "I'm looking for",
        "May I have",
        "How do I",
        "What time is"
    ]
}

/// Cloud translation over a REST API (Google v2 or Microsoft Translator 3.0).
/// The key is the parent's own; nothing is proxied through us. The source and
/// target languages are both chosen by the user (front → back).
struct CloudTranslator: Translator {
    let provider: TranslationProvider
    let apiKey: String
    let source: AnswerLanguage
    let target: AnswerLanguage
    /// Azure region for Microsoft Translator (e.g. "eastus"). Required as the
    /// `Ocp-Apim-Subscription-Region` header for a regional key, or the service
    /// returns 401. Ignored by Google. A regional Translator key WILL 401
    /// without it — this was the cause of the 401 seen in the field.
    var region: String = ""

    /// The key with *all* whitespace removed — not just the ends. API keys are
    /// unbroken tokens with no internal spaces, yet pasting one on iOS commonly
    /// slips in a stray space or newline (mid-string), which is invisible behind
    /// a masked field and is a silent cause of 401. Stripping every whitespace
    /// character makes a mis-pasted key work instead of failing mysteriously.
    private var trimmedKey: String {
        apiKey.filter { !$0.isWhitespace }
    }

    func translate(_ texts: [String]) async throws -> [String] {
        guard !trimmedKey.isEmpty else { throw CloudTranslationError.missingKey }
        guard !texts.isEmpty else { return [] }
        switch provider {
        case .apple:
            // Apple isn't a REST engine; callers use AppleTranslator instead.
            throw CloudTranslationError.badResponse
        case .google:
            return try await translateWithGoogle(texts)
        case .microsoft:
            return try await translateWithMicrosoft(texts)
        }
    }

    // MARK: Google Cloud Translation v2

    private func translateWithGoogle(_ texts: [String]) async throws -> [String] {
        var components = URLComponents(string: "https://translation.googleapis.com/language/translate/v2")!
        components.queryItems = [URLQueryItem(name: "key", value: trimmedKey)]
        guard let url = components.url else { throw CloudTranslationError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "q": texts,
            "source": source.code,
            "target": target.code,
            "format": "text"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let dataObj = root["data"] as? [String: Any],
            let translations = dataObj["translations"] as? [[String: Any]]
        else { throw CloudTranslationError.badResponse }
        // Google preserves input order.
        let results = translations.map { ($0["translatedText"] as? String) ?? "" }
        return normalize(results, count: texts.count)
    }

    // MARK: Microsoft Translator 3.0

    private func translateWithMicrosoft(_ texts: [String]) async throws -> [String] {
        var components = URLComponents(string: "https://api.cognitive.microsofttranslator.com/translate")!
        components.queryItems = [
            URLQueryItem(name: "api-version", value: "3.0"),
            URLQueryItem(name: "from", value: source.code),
            URLQueryItem(name: "to", value: target.code)
        ]
        guard let url = components.url else { throw CloudTranslationError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(trimmedKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        // A regional Translator key requires the region header against the global
        // endpoint; without it Microsoft rejects the request with 401.
        let trimmedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedRegion.isEmpty {
            request.setValue(trimmedRegion, forHTTPHeaderField: "Ocp-Apim-Subscription-Region")
        }
        let body = texts.map { ["Text": $0] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let items = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw CloudTranslationError.badResponse }
        let results = items.map { item -> String in
            let translations = item["translations"] as? [[String: Any]]
            return (translations?.first?["text"] as? String) ?? ""
        }
        return normalize(results, count: texts.count)
    }

    // MARK: Helpers

    private func send(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudTranslationError.badResponse }
            guard (200..<300).contains(http.statusCode) else {
                throw CloudTranslationError.network(serviceError(from: data, status: http.statusCode))
            }
            return data
        } catch let error as CloudTranslationError {
            throw error
        } catch {
            throw CloudTranslationError.network(error.localizedDescription)
        }
    }

    /// Turn a non-2xx response body into a readable message. Both Google and
    /// Microsoft nest the detail under `error` as `{code, message}`, so surfacing
    /// it tells a parent *why* (bad key vs bad region vs wrong endpoint) instead
    /// of a bare "status 401".
    private func serviceError(from data: Data, status: Int) -> String {
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = root["error"] as? [String: Any] {
            let code = (error["code"] as? Int).map(String.init)
                ?? (error["code"] as? String)
            let message = error["message"] as? String
            switch (code, message) {
            case let (code?, message?): return "status \(status) (\(code)): \(message)"
            case let (code?, nil): return "status \(status) (\(code))"
            case let (nil, message?): return "status \(status): \(message)"
            default: break
            }
        }
        return "status \(status)"
    }

    /// Pad or trim to match the request count so cards line up by index.
    private func normalize(_ results: [String], count: Int) -> [String] {
        if results.count == count { return results }
        var out = results
        if out.count > count { out = Array(out.prefix(count)) }
        while out.count < count { out.append("") }
        return out
    }
}

/// Stores each cloud provider's API key in the Keychain, keeping it out of the
/// SwiftData store and backups-in-plaintext. Keys are kept **per provider**: a
/// Google key and a Microsoft key are different secrets, so storing one shared
/// value meant switching the engine picker silently carried (say) an Azure key
/// over to Google, which then failed. Each provider now has its own slot.
enum CloudTranslationKey {
    private static let service = "com.flipstudy.app.translation"
    /// The old single-slot account, before keys were split per provider. Kept
    /// only so an upgrading user's already-entered key can be migrated once.
    private static let legacyAccount = "cloudTranslationAPIKey"

    private static func account(for provider: TranslationProvider) -> String {
        "cloudTranslationAPIKey.\(provider.rawValue)"
    }

    static func read(for provider: TranslationProvider) -> String {
        readRaw(account: account(for: provider))
    }

    static func save(_ value: String, for provider: TranslationProvider) {
        // Strip every whitespace character, not just the ends: a stray space or
        // newline slipped into the middle of a pasted key is invisible behind a
        // masked field and otherwise causes a mystifying 401.
        writeRaw(value.filter { !$0.isWhitespace }, account: account(for: provider))
    }

    /// One-time move of the old single shared key onto the provider that was
    /// active when it was entered. Without this an upgrading user would lose the
    /// key they already pasted — and re-pasting a masked key is exactly the pain
    /// we're trying to end. Safe to call repeatedly; a no-op once migrated.
    static func migrateLegacyKey(to provider: TranslationProvider) {
        let legacy = readRaw(account: legacyAccount)
        guard !legacy.isEmpty else { return }
        if readRaw(account: account(for: provider)).isEmpty {
            writeRaw(legacy, account: account(for: provider))
        }
        deleteRaw(account: legacyAccount)
    }

    // MARK: - Keychain primitives

    private static func readRaw(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return "" }
        return value
    }

    private static func writeRaw(_ value: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private static func deleteRaw(account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
    }
}
