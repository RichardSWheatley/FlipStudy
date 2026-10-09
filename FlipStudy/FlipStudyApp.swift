import SwiftUI
import SwiftData

@main
struct FlipStudyApp: App {
    /// App-scoped so entitlement state and the transaction listener live for the
    /// whole session and every view reads the same Pro status.
    @State private var proStore = ProStore()
    /// Hands a family code from a tapped join link to Settings.
    @State private var linkRouter = FamilyLinkRouter()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(proStore)
                .environment(linkRouter)
                // A tapped join link arrives here whether the app was running
                // or not. SwiftUI delivers universal links through both paths
                // depending on how the app was opened, so listen on both.
                .onOpenURL { linkRouter.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { linkRouter.handle(url) }
                }
        }
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self, StudyDay.self])
    }
}
