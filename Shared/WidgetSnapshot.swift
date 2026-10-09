import Foundation

/// What the widget shows, written by the app whenever study state changes.
///
/// A widget can't open the app's database, so the app hands it this small
/// summary through the shared App Group. It carries every card's due date
/// rather than a single count so the widget can keep its number right on its
/// own timeline — cards come due while the app is closed.
struct WidgetSnapshot: Codable, Equatable {
    /// Each card's next due date; nil means due now.
    var dueDates: [Date?]
    /// Consecutive study days ending at `lastStudyDay`.
    var streakLength: Int
    var lastStudyDay: Date?
    /// Cards reviewed on `day`.
    var reviewedToday: Int
    var dailyGoal: Int
    /// The day `reviewedToday` was counted on.
    var day: Date

    static let appGroup = "group.com.flipstudy.app"
    private static let key = "widgetSnapshot"

    func dueCount(at date: Date) -> Int {
        dueDates.filter { ($0 ?? .distantPast) <= date }.count
    }

    /// Today's progress — zero once the day the snapshot counted has passed.
    func reviewed(on date: Date, calendar: Calendar = .current) -> Int {
        calendar.isDate(day, inSameDayAs: date) ? reviewedToday : 0
    }

    /// The streak as of `date`: still alive while the last study day was today
    /// or yesterday, gone after that.
    func streak(on date: Date, calendar: Calendar = .current) -> Int {
        guard let lastStudyDay else { return 0 }
        let today = calendar.startOfDay(for: date)
        let last = calendar.startOfDay(for: lastStudyDay)
        let gap = calendar.dateComponents([.day], from: last, to: today).day ?? .max
        return gap <= 1 ? streakLength : 0
    }

    static func load(defaults: UserDefaults? = UserDefaults(suiteName: appGroup)) -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(defaults: UserDefaults? = UserDefaults(suiteName: WidgetSnapshot.appGroup)) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
