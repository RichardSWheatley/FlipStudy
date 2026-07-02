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
    var translationProviderRaw: String

    var translationProvider: TranslationProvider {
        get { TranslationProvider(rawValue: translationProviderRaw) ?? .apple }
        set { translationProviderRaw = newValue.rawValue }
    }

    init(cloudAIEnabled: Bool = false,
         translationProviderRaw: String = TranslationProvider.apple.rawValue) {
        self.cloudAIEnabled = cloudAIEnabled
        self.translationProviderRaw = translationProviderRaw
    }
}
