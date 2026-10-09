import Foundation
import UserNotifications

/// The daily "cards are ready" reminder, as local notifications — nothing
/// leaves the phone.
///
/// Rather than one repeating notification with a fixed message, the next week
/// is scheduled day by day, each saying how many cards will actually be due at
/// that moment, and days with nothing due get no reminder at all. It's
/// rescheduled whenever studying changes the due dates.
enum StudyNotifier {
    static let identifierPrefix = "flipstudy.study."

    /// Ask for permission to send reminders. True if allowed.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// When to remind, and how many cards will be waiting each time. Pure, so
    /// the rules can be tested without the notification system.
    static func plan(dueDates: [Date?], now: Date, minutesAfterMidnight: Int,
                     days: Int = 7, calendar: Calendar = .current) -> [(date: Date, due: Int)] {
        var plan: [(date: Date, due: Int)] = []
        let today = calendar.startOfDay(for: now)
        for offset in 0..<days {
            guard let base = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: base),
                  fire > now
            else { continue }
            let due = dueDates.filter { ($0 ?? .distantPast) <= fire }.count
            if due > 0 { plan.append((fire, due)) }
        }
        return plan
    }

    static func message(due: Int) -> String {
        due == 1 ? "1 card is ready to study." : "\(due) cards are ready to study."
    }

    /// Replace FlipStudy's pending reminders with a fresh week of them.
    static func reschedule(enabled: Bool, minutesAfterMidnight: Int, dueDates: [Date?], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard enabled else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        for item in plan(dueDates: dueDates, now: now, minutesAfterMidnight: minutesAfterMidnight) {
            let content = UNMutableNotificationContent()
            content.title = "FlipStudy"
            content.body = message(due: item.due)
            content.sound = .default
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + String(Int(item.date.timeIntervalSince1970)),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
