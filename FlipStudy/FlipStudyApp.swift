import SwiftUI
import SwiftData

@main
struct FlipStudyApp: App {
    /// App-scoped so entitlement state and the transaction listener live for the
    /// whole session and every view reads the same Pro status.
    @State private var proStore = ProStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(proStore)
        }
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self])
    }
}
