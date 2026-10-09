import XCTest
@testable import FlipStudy__Flashcards

/// Streaks, the daily goal, the reminder schedule and the widget's numbers all
/// come from small pure rules, so the edge cases are pinned down here: a streak
/// must not vanish just because today hasn't been studied yet, and a reminder
/// must never fire on a day with nothing due.
final class StudyProgressTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: - Streaks

    func test_streak_countsConsecutiveDaysEndingAtTheLatest() {
        let days = [day(2026, 10, 5), day(2026, 10, 6), day(2026, 10, 7)]
        let result = StudyProgress.streak(studyDays: days, calendar: calendar)
        XCTAssertEqual(result.length, 3)
    }

    func test_streak_stopsAtAGap() {
        let days = [day(2026, 10, 2), day(2026, 10, 5), day(2026, 10, 6)]
        XCTAssertEqual(StudyProgress.streak(studyDays: days, calendar: calendar).length, 2)
    }

    func test_streak_ignoresSeveralSessionsOnTheSameDay() {
        let days = [day(2026, 10, 6, 8), day(2026, 10, 6, 20), day(2026, 10, 7)]
        XCTAssertEqual(StudyProgress.streak(studyDays: days, calendar: calendar).length, 2)
    }

    func test_currentStreak_survivesUntilToday_isStudied() {
        // Studied yesterday, not yet today: the streak is still alive.
        let days = [day(2026, 10, 6), day(2026, 10, 7)]
        XCTAssertEqual(StudyProgress.currentStreak(studyDays: days, now: day(2026, 10, 8, 9), calendar: calendar), 2)
    }

    func test_currentStreak_isGoneAfterAMissedDay() {
        let days = [day(2026, 10, 6), day(2026, 10, 7)]
        XCTAssertEqual(StudyProgress.currentStreak(studyDays: days, now: day(2026, 10, 9, 9), calendar: calendar), 0)
    }

    func test_currentStreak_isZeroWithNoStudy() {
        XCTAssertEqual(StudyProgress.currentStreak(studyDays: [], calendar: calendar), 0)
    }

    // MARK: - Reminder schedule

    func test_plan_countsCardsDueAtEachReminder_andSkipsDaysWithNothingDue() {
        let now = day(2026, 10, 8, 9)
        // One card due now, one due on the 10th at noon, nothing else.
        let due: [Date?] = [nil, day(2026, 10, 10, 12)]
        let plan = StudyNotifier.plan(dueDates: due, now: now, minutesAfterMidnight: 17 * 60, days: 4, calendar: calendar)
        XCTAssertEqual(plan.map(\.due), [1, 1, 2, 2])
        XCTAssertEqual(plan.first?.date, day(2026, 10, 8, 17))
    }

    func test_plan_skipsTodayOnceTheTimeHasPassed() {
        let now = day(2026, 10, 8, 18)
        let plan = StudyNotifier.plan(dueDates: [nil], now: now, minutesAfterMidnight: 17 * 60, days: 2, calendar: calendar)
        XCTAssertEqual(plan.map(\.date), [day(2026, 10, 9, 17)])
    }

    func test_plan_isEmptyWhenNothingWillBeDue() {
        let plan = StudyNotifier.plan(dueDates: [day(2027, 1, 1)], now: day(2026, 10, 8, 9),
                                      minutesAfterMidnight: 17 * 60, days: 7, calendar: calendar)
        XCTAssertTrue(plan.isEmpty)
    }

    func test_message_isSingularForOneCard() {
        XCTAssertEqual(StudyNotifier.message(due: 1), "1 card is ready to study.")
        XCTAssertEqual(StudyNotifier.message(due: 12), "12 cards are ready to study.")
    }

    // MARK: - Widget snapshot

    func test_snapshot_dueCountGrowsAsCardsComeDue() {
        let snapshot = WidgetSnapshot(dueDates: [nil, day(2026, 10, 8, 15), day(2026, 10, 9)],
                                      streakLength: 1, lastStudyDay: day(2026, 10, 8),
                                      reviewedToday: 5, dailyGoal: 20, day: day(2026, 10, 8, 9))
        XCTAssertEqual(snapshot.dueCount(at: day(2026, 10, 8, 10)), 1)
        XCTAssertEqual(snapshot.dueCount(at: day(2026, 10, 8, 16)), 2)
    }

    func test_snapshot_todaysProgressResetsAtMidnight_andTheStreakLapsesAfterAMissedDay() {
        let snapshot = WidgetSnapshot(dueDates: [], streakLength: 3, lastStudyDay: day(2026, 10, 8),
                                      reviewedToday: 12, dailyGoal: 20, day: day(2026, 10, 8, 20))
        XCTAssertEqual(snapshot.reviewed(on: day(2026, 10, 8, 23), calendar: calendar), 12)
        XCTAssertEqual(snapshot.reviewed(on: day(2026, 10, 9, 8), calendar: calendar), 0)
        XCTAssertEqual(snapshot.streak(on: day(2026, 10, 9, 8), calendar: calendar), 3)
        XCTAssertEqual(snapshot.streak(on: day(2026, 10, 10, 8), calendar: calendar), 0)
    }

    func test_snapshot_roundTripsThroughDefaults() {
        let defaults = UserDefaults(suiteName: "test.widgetSnapshot.\(UUID().uuidString)")!
        let snapshot = WidgetSnapshot(dueDates: [nil, day(2026, 10, 9)], streakLength: 2, lastStudyDay: day(2026, 10, 8),
                                      reviewedToday: 4, dailyGoal: 25, day: day(2026, 10, 8))
        snapshot.save(defaults: defaults)
        XCTAssertEqual(WidgetSnapshot.load(defaults: defaults), snapshot)
    }
}
