import Foundation
import Observation

/// Carries a family code that arrived by link to the screen that redeems it.
///
/// A tester gets one join link by text, e.g.
/// `https://flipstudy-cards.richardswheatley.workers.dev/join?code=FLIP-A7K2-9QX4`.
/// Without FlipStudy, that page offers the TestFlight install; with FlipStudy,
/// iOS opens the app instead (a universal link) and the code lands here. It
/// still goes through the grown-up check — a link must never switch on
/// something that sends text off the phone by itself.
@Observable
final class FamilyLinkRouter {
    /// The host that serves join links and Apple's site-association file.
    static let host = CloudCardGenerator.endpoint.host() ?? ""

    /// A code waiting to be redeemed, already normalized. Cleared once the
    /// grown-up check has been offered for it.
    var pendingCode: String?

    /// Accept only our own join links with a plausible code; anything else
    /// that opens the app is ignored rather than guessed at.
    func handle(_ url: URL) {
        // The App Store build has no family codes (see `Distribution`).
        guard Distribution.allowsFamilyCodes,
              url.host() == Self.host,
              url.path() == "/join",
              let code = FamilyAccess.normalized(url.absoluteString)
        else { return }
        pendingCode = code
    }
}
