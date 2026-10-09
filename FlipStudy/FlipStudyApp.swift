import SwiftUI
import SwiftData

@main
struct FlipStudyApp: App {
    /// App-scoped so entitlement state and the transaction listener live for the
    /// whole session and every view reads the same Pro status.
    @State private var proStore = ProStore()
    /// Hands a family code from a tapped join link to Settings.
    @State private var linkRouter = FamilyLinkRouter()
    /// Built once: decks sync through iCloud, settings stay on this device.
    private let container: ModelContainer
    /// The colour picked in Settings, which also drives the icon and widget.
    @AppStorage(AppTheme.storageKey, store: AppTheme.defaults) private var themeRaw = AppTheme.classic.rawValue

    init() {
        #if DEBUG
        CloudSchema.initializeIfRequested()
        #endif
        container = Persistence.makeContainer()
        Task { await Distribution.refresh() }
        #if DEBUG
        DemoDecks.insertIfRequested(into: container.mainContext)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(proStore)
                .environment(linkRouter)
                // Rounded type and the picked colour everywhere: friendlier
                // for the kids this is for.
                .fontDesign(.rounded)
                .tint((AppTheme(rawValue: themeRaw) ?? .classic).bottom)
                // A tapped join link arrives here whether the app was running
                // or not. SwiftUI delivers universal links through both paths
                // depending on how the app was opened, so listen on both.
                .onOpenURL { linkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { linkRouter.handle(url) }
                }
        }
        .modelContainer(container)
    }
}
