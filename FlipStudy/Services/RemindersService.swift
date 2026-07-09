import Foundation
import EventKit

/// Creates study reminders in the system Reminders app via EventKit.
///
/// Reminders only offers "full access" (there's no write-only tier the way
/// Calendar has), so the first use shows the system permission prompt backed by
/// `NSRemindersFullAccessUsageDescription`. Nothing is stored by us — the
/// reminder lives in the user's own Reminders list.
@Observable
final class RemindersService {
    private let store = EKEventStore()

    enum ReminderError: LocalizedError {
        case accessDenied
        case noList

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "FlipStudy needs permission to add Reminders. You can turn it on in Settings › FlipStudy › Reminders."
            case .noList:
                return "No Reminders list is available to add to."
            }
        }
    }

    /// Ask for Reminders access (shows the system prompt the first time).
    func requestAccess() async throws {
        let granted = try await store.requestFullAccessToReminders()
        guard granted else { throw ReminderError.accessDenied }
    }

    /// Add a reminder due at `date` with an alarm so it actually alerts. Requests
    /// access first if needed. Returns the date it was scheduled for.
    @discardableResult
    func addStudyReminder(title: String, notes: String? = nil, due date: Date) async throws -> Date {
        if EKEventStore.authorizationStatus(for: .reminder) != .fullAccess {
            try await requestAccess()
        }
        guard let list = store.defaultCalendarForNewReminders() else {
            throw ReminderError.noList
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = title
        reminder.notes = notes
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: date
        )
        reminder.addAlarm(EKAlarm(absoluteDate: date))

        try store.save(reminder, commit: true)
        return date
    }
}
