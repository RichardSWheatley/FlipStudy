import Foundation
import StoreKit

/// Where this copy of FlipStudy came from, as far as family codes care.
///
/// App Review doesn't allow codes or QR codes that unlock features (Guideline
/// 3.1.1), so family codes — and FlipStudy Cloud, which they unlock — exist only
/// in TestFlight and development builds. The App Store build behaves as if no
/// code was ever redeemed: no "Enter Family Code", no join links, no cloud.
enum Distribution {
    private static let cacheKey = "distribution.allowsFamilyCodes"

    /// True in TestFlight and development builds. Starts from what the last
    /// launch learned, so a TestFlight family member never sees FlipStudy
    /// Cloud flicker off while `refresh()` runs; a fresh install starts closed.
    static private(set) var allowsFamilyCodes: Bool = {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: cacheKey)
        #endif
    }()

    /// Ask the App Store's own signed record of this install. Call at launch.
    @MainActor
    static func refresh() async {
        #if !DEBUG
        guard let result = try? await AppTransaction.shared else { return }
        let transaction: AppTransaction
        switch result {
        case .verified(let verified): transaction = verified
        case .unverified(let unverified, _): transaction = unverified
        }
        // TestFlight installs report the sandbox environment.
        let allowed = transaction.environment != .production
        allowsFamilyCodes = allowed
        UserDefaults.standard.set(allowed, forKey: cacheKey)
        #endif
    }
}
