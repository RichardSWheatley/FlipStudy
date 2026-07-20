import Foundation
import SwiftData

/// App-wide settings. The cloud API key is NOT stored here — it lives in the
/// Keychain (see `CloudTranslationKey`). This flag only records whether the
/// parent has enabled the cloud path, plus which translation engine to use.
@Model
final class AppSettings {
    /// Whether the parent has unlocked the cloud path via the grown-up gate.
    var cloudAIEnabled: Bool

    /// Raw value of the selected `TranslationProvider`. Apple's on-device engine
    /// is the default; cloud engines require `cloudAIEnabled` and an API key.
    /// The declaration default is required so SwiftData can backfill existing
    /// rows when migrating a store made before this property existed.
    var translationProviderRaw: String = TranslationProvider.apple.rawValue

    var translationProvider: TranslationProvider {
        get { TranslationProvider(rawValue: translationProviderRaw) ?? .apple }
        set { translationProviderRaw = newValue.rawValue }
    }

    /// Azure region for the Microsoft Translator resource (e.g. "eastus"). The
    /// global endpoint with a regional key REQUIRES this as the
    /// `Ocp-Apim-Subscription-Region` header, or Microsoft returns 401. It's not
    /// a secret, so it lives here rather than the Keychain. Unused by Google.
    /// The declaration default lets SwiftData backfill stores made before it
    /// existed.
    var cloudTranslationRegion: String = ""

    init(cloudAIEnabled: Bool = false,
         translationProviderRaw: String = TranslationProvider.apple.rawValue,
         cloudTranslationRegion: String = "") {
        self.cloudAIEnabled = cloudAIEnabled
        self.translationProviderRaw = translationProviderRaw
        self.cloudTranslationRegion = cloudTranslationRegion
    }
}
