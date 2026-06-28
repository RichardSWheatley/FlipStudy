import Foundation
import SwiftData

/// App-wide settings. The cloud-AI API key is NOT stored here — it lives in the
/// Keychain (added in Phase 5). This flag only records whether the parent has
/// enabled the cloud path.
@Model
final class AppSettings {
    var cloudAIEnabled: Bool

    init(cloudAIEnabled: Bool = false) {
        self.cloudAIEnabled = cloudAIEnabled
    }
}
