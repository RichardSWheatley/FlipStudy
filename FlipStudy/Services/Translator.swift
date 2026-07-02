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
        case .english: "English (no translation)"
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

/// Cloud translation over a REST API (Google v2 or Microsoft Translator 3.0).
/// The key is the parent's own; nothing is proxied through us. English is the
/// fixed source language, matching the rest of the app.
struct CloudTranslator: Translator {
    let provider: TranslationProvider
    let apiKey: String
    let target: AnswerLanguage

    func translate(_ texts: [String]) async throws -> [String] {
        guard !apiKey.isEmpty else { throw CloudTranslationError.missingKey }
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
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw CloudTranslationError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "q": texts,
            "source": "en",
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
            URLQueryItem(name: "from", value: "en"),
            URLQueryItem(name: "to", value: target.code)
        ]
        guard let url = components.url else { throw CloudTranslationError.badResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
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
                throw CloudTranslationError.network("status \(http.statusCode)")
            }
            return data
        } catch let error as CloudTranslationError {
            throw error
        } catch {
            throw CloudTranslationError.network(error.localizedDescription)
        }
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

/// Stores the cloud translation API key in the Keychain, keeping it out of the
/// SwiftData store and backups-in-plaintext. One shared key for the app.
enum CloudTranslationKey {
    private static let account = "cloudTranslationAPIKey"
    private static let service = "com.flipstudy.app.translation"

    static func read() -> String {
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

    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
