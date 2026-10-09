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

    /// Whether a FlipStudy Cloud family code has been redeemed on this phone.
    /// The token itself lives in the Keychain (`FamilyAccess`); this flag is
    /// the part views read, so SwiftUI redraws the moment a code is entered.
    /// Declaration defaults let SwiftData backfill stores made before these
    /// properties existed.
    var cloudCardsEnabled: Bool = false

    /// Which code is in use ("Sam's iPhone"), shown in Settings so a parent can
    /// tell at a glance whose access this is.
    var cloudCardsLabel: String = ""

    /// Set when the user would rather keep making cards on the phone even
    /// though cloud is unlocked. A privacy choice, so it is never overridden.
    var prefersOnDeviceCards: Bool = false

    /// Whether the daily "cards are ready" notification is on.
    var reminderEnabled: Bool = false
    /// When it fires, as minutes after midnight (17:00 by default — after school).
    var reminderMinutes: Int = AppSettings.defaultReminderMinutes
    /// Cards a day that count as meeting the goal.
    var dailyGoal: Int = AppSettings.defaultDailyGoal

    static let defaultReminderMinutes = 17 * 60
    static let defaultDailyGoal = 20

    init(cloudAIEnabled: Bool = false,
         translationProviderRaw: String = TranslationProvider.apple.rawValue,
         cloudTranslationRegion: String = "",
         cloudCardsEnabled: Bool = false,
         cloudCardsLabel: String = "",
         prefersOnDeviceCards: Bool = false) {
        self.cloudAIEnabled = cloudAIEnabled
        self.translationProviderRaw = translationProviderRaw
        self.cloudTranslationRegion = cloudTranslationRegion
        self.cloudCardsEnabled = cloudCardsEnabled
        self.cloudCardsLabel = cloudCardsLabel
        self.prefersOnDeviceCards = prefersOnDeviceCards
    }
}
