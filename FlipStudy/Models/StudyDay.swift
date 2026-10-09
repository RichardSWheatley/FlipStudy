import Foundation
import SwiftData

/// One calendar day of studying: how many cards were reviewed. Streaks and the
/// daily goal are worked out from these.
///
/// Every property has a default because iCloud sync (CloudKit) requires it;
/// two devices may each create a row for the same day once sync is on, so
/// readers sum by day rather than assuming one row per day.
@Model
final class StudyDay {
    /// Start of the calendar day this row counts.
    var day: Date = Date.distantPast
    var reviewCount: Int = 0

    init(day: Date, reviewCount: Int = 0) {
        self.day = day
        self.reviewCount = reviewCount
    }
}
