import Foundation
import SwiftData
import os

/// Where FlipStudy keeps its data.
///
/// Decks, cards and study days sync through the user's own iCloud account —
/// their private CloudKit database, which nobody else (FlipStudy included) can
/// read. Settings stay on each device: they describe *this* phone (its family
/// code, its reminder time), and a synced settings row would be duplicated by
/// every device that starts up before the first sync arrives.
enum Persistence {
    static let cloudContainerID = "iCloud.com.flipstudy.app"

    /// Whether this launch syncs with iCloud. False when the store had to fall
    /// back to this device alone, e.g. a build without the iCloud entitlement.
    private(set) static var isSyncing = false

    /// The single store FlipStudy used before sync. It keeps the decks and
    /// becomes the synced store, so nothing has to be copied.
    ///
    /// Both paths are spelled out on purpose. Once the app has an App Group
    /// (the widget's), SwiftData's *default* location moves into the group
    /// container — which would open an empty store and strand every deck
    /// people already have here.
    private static func mainStoreURL(in directory: URL) -> URL { directory.appending(path: "default.store") }
    private static func settingsStoreURL(in directory: URL) -> URL { directory.appending(path: "Settings.store") }

    private static let log = Logger(subsystem: "com.flipstudy.app", category: "Persistence")

    private static let syncedSchema = Schema([Deck.self, Card.self, StudyDay.self])
    private static let fullSchema = Schema([Deck.self, Card.self, StudyDay.self, AppSettings.self])

    /// `directory` and `allowSync` exist for tests; the app takes the defaults.
    @MainActor
    static func makeContainer(in directory: URL = .applicationSupportDirectory,
                              allowSync: Bool = true) -> ModelContainer {
        let carried = carryOverSettings(in: directory)

        let container: ModelContainer
        if allowSync, let synced = open(in: directory, syncing: true) {
            container = synced
            isSyncing = true
        } else if let local = open(in: directory, syncing: false) {
            container = local
        } else {
            // Never refuse to launch: an empty session beats a crash loop.
            container = try! ModelContainer(for: fullSchema,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }

        if let carried {
            let context = container.mainContext
            if (try? context.fetchCount(FetchDescriptor<AppSettings>())) == 0 {
                context.insert(carried.makeSettings())
                try? context.save()
            }
        }
        return container
    }

    private static func open(in directory: URL, syncing: Bool) -> ModelContainer? {
        let synced = ModelConfiguration("Synced", schema: syncedSchema, url: mainStoreURL(in: directory),
                                        cloudKitDatabase: syncing ? .private(cloudContainerID) : .none)
        // Explicitly local: left at `.automatic`, SwiftData would sync this too.
        let local = ModelConfiguration("Settings", schema: Schema([AppSettings.self]),
                                       url: settingsStoreURL(in: directory), cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: fullSchema, configurations: synced, local)
        } catch {
            log.error("Couldn't open the store (syncing: \(syncing)): \(error)")
            return nil
        }
    }

    // MARK: - Moving settings out of the old store

    /// Before sync, settings lived in the main store. The first launch with
    /// sync copies them to the settings store, so a redeemed family code stays
    /// switched on and the reminder keeps its time. Runs once: afterwards the
    /// settings store exists.
    private static func carryOverSettings(in directory: URL) -> SettingsSnapshot? {
        let files = FileManager.default
        guard !files.fileExists(atPath: settingsStoreURL(in: directory).path(percentEncoded: false)),
              files.fileExists(atPath: mainStoreURL(in: directory).path(percentEncoded: false))
        else { return nil }

        let legacy = ModelConfiguration(schema: fullSchema, url: mainStoreURL(in: directory), cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: fullSchema, configurations: legacy)
            guard let old = try ModelContext(container).fetch(FetchDescriptor<AppSettings>()).first else { return nil }
            return SettingsSnapshot(old)
        } catch {
            log.error("Couldn't read settings from the old store: \(error)")
            return nil
        }
    }

    /// Plain values, so nothing from the old store outlives it.
    private struct SettingsSnapshot {
        let cloudAIEnabled: Bool
        let translationProviderRaw: String
        let cloudTranslationRegion: String
        let cloudCardsEnabled: Bool
        let cloudCardsLabel: String
        let prefersOnDeviceCards: Bool
        let reminderEnabled: Bool
        let reminderMinutes: Int
        let dailyGoal: Int

        init(_ settings: AppSettings) {
            cloudAIEnabled = settings.cloudAIEnabled
            translationProviderRaw = settings.translationProviderRaw
            cloudTranslationRegion = settings.cloudTranslationRegion
            cloudCardsEnabled = settings.cloudCardsEnabled
            cloudCardsLabel = settings.cloudCardsLabel
            prefersOnDeviceCards = settings.prefersOnDeviceCards
            reminderEnabled = settings.reminderEnabled
            reminderMinutes = settings.reminderMinutes
            dailyGoal = settings.dailyGoal
        }

        func makeSettings() -> AppSettings {
            let settings = AppSettings(cloudAIEnabled: cloudAIEnabled,
                                       translationProviderRaw: translationProviderRaw,
                                       cloudTranslationRegion: cloudTranslationRegion,
                                       cloudCardsEnabled: cloudCardsEnabled,
                                       cloudCardsLabel: cloudCardsLabel,
                                       prefersOnDeviceCards: prefersOnDeviceCards)
            settings.reminderEnabled = reminderEnabled
            settings.reminderMinutes = reminderMinutes
            settings.dailyGoal = dailyGoal
            return settings
        }
    }
}
