import SwiftUI
import SwiftData

@main
struct FlipStudyApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .modelContainer(for: [Deck.self, Card.self, AppSettings.self])
    }
}
