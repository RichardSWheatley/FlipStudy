import Foundation
import SwiftData
import WidgetKit

/// Streaks, the daily goal, and keeping the widget and reminders current.
enum StudyProgress {

    /// Count one reviewed card toward today.
    static func recordReview(in context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: now)
        let descriptor = FetchDescriptor<StudyDay>(predicate: #Predicate { $0.day == start })
        if let today = try? context.fetch(descriptor).first {
            today.reviewCount += 1
        } else {
            context.insert(StudyDay(day: start, reviewCount: 1))
        }
    }

    /// Consecutive study days ending at the most recent one.
    static func streak(studyDays: [Date], calendar: Calendar = .current) -> (length: Int, lastDay: Date?) {
        let days = Set(studyDays.map { calendar.startOfDay(for: $0) })
        guard let last = days.max() else { return (0, nil) }
        var length = 0
        var cursor = last
        while days.contains(cursor) {
            length += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return (length, last)
    }

    /// The streak someone sees right now: alive while they studied today or
    /// yesterday, so it doesn't reset just because today hasn't happened yet.
    static func currentStreak(studyDays: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let (length, last) = streak(studyDays: studyDays, calendar: calendar)
        guard let last else { return 0 }
        let gap = calendar.dateComponents([.day], from: last, to: calendar.startOfDay(for: now)).day ?? .max
        return gap <= 1 ? length : 0
    }

    /// Cards reviewed on `now`'s day, summed across rows (sync can make two).
    static func reviewed(on now: Date, in days: [StudyDay], calendar: Calendar = .current) -> Int {
        days.filter { calendar.isDate($0.day, inSameDayAs: now) }.reduce(0) { $0 + $1.reviewCount }
    }

    /// Bring the widget and the daily reminders up to date with the store.
    /// Cheap enough to call whenever studying ends or the app leaves the screen.
    @MainActor
    static func refresh(context: ModelContext, settings: AppSettings?, now: Date = .now) {
        let cards = (try? context.fetch(FetchDescriptor<Card>())) ?? []
        let days = (try? context.fetch(FetchDescriptor<StudyDay>())) ?? []
        let dueDates = cards.map(\.nextDue)
        let studied = days.filter { $0.reviewCount > 0 }.map(\.day)
        let (length, last) = streak(studyDays: studied)

        WidgetSnapshot(
            dueDates: Array(dueDates.prefix(2000)),
            streakLength: length,
            lastStudyDay: last,
            reviewedToday: reviewed(on: now, in: days),
            dailyGoal: settings?.dailyGoal ?? AppSettings.defaultDailyGoal,
            day: now
        ).save()
        WidgetCenter.shared.reloadAllTimelines()

        let enabled = settings?.reminderEnabled ?? false
        let minutes = settings?.reminderMinutes ?? AppSettings.defaultReminderMinutes
        Task { await StudyNotifier.reschedule(enabled: enabled, minutesAfterMidnight: minutes, dueDates: dueDates) }
    }
}
