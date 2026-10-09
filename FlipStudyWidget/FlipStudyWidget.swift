import SwiftUI
import WidgetKit

/// Home- and lock-screen widget: how many cards are due, and the streak.
///
/// Reads the summary the app leaves in the shared App Group. Because that
/// summary holds each card's due date, the timeline can step forward as cards
/// come due without the app running.
struct StudyEntry: TimelineEntry {
    let date: Date
    let due: Int
    let streak: Int
    let reviewed: Int
    let goal: Int
    let hasData: Bool

    static let sample = StudyEntry(date: .now, due: 12, streak: 4, reviewed: 8, goal: 20, hasData: true)
}

struct StudyProvider: TimelineProvider {
    func placeholder(in context: Context) -> StudyEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> Void) {
        completion(context.isPreview ? .sample : entry(at: .now, from: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> Void) {
        let snapshot = WidgetSnapshot.load()
        let now = Date.now
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now

        // A new entry at each moment the count changes over the next day —
        // every upcoming due date — plus midnight, when today's progress resets.
        let horizon = now.addingTimeInterval(24 * 60 * 60)
        let changes = Set((snapshot?.dueDates ?? []).compactMap { $0 }.filter { $0 > now && $0 <= horizon })
        let moments = ([now, midnight] + changes).sorted().prefix(40)

        let entries = moments.map { entry(at: $0, from: snapshot) }
        completion(Timeline(entries: Array(entries), policy: .after(horizon)))
    }

    private func entry(at date: Date, from snapshot: WidgetSnapshot?) -> StudyEntry {
        guard let snapshot else {
            return StudyEntry(date: date, due: 0, streak: 0, reviewed: 0, goal: 20, hasData: false)
        }
        return StudyEntry(date: date,
                          due: snapshot.dueCount(at: date),
                          streak: snapshot.streak(on: date),
                          reviewed: snapshot.reviewed(on: date),
                          goal: max(snapshot.dailyGoal, 1),
                          hasData: true)
    }
}

struct StudyWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StudyEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("\(entry.due)").font(.title2.weight(.bold)).minimumScaleFactor(0.5)
                    Text("due").font(.caption2)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("FlipStudy").font(.headline)
                Text(dueLine)
                if entry.streak > 0 {
                    Label("\(entry.streak)-day streak", systemImage: "flame.fill")
                }
            }
        case .accessoryInline:
            Text(entry.streak > 0 ? "\(entry.due) due · \(entry.streak)-day streak" : dueLine)
        default:
            small
        }
    }

    private var dueLine: String {
        entry.due == 1 ? "1 card due" : "\(entry.due) cards due"
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .foregroundStyle(.tint)
                Spacer()
                if entry.streak > 0 {
                    Label("\(entry.streak)", systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
            if entry.hasData {
                Text("\(entry.due)")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                Text(entry.due == 1 ? "card due" : "cards due")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: Double(min(entry.reviewed, entry.goal)), total: Double(entry.goal))
                    .tint(entry.reviewed >= entry.goal ? .green : .accentColor)
            } else {
                Text("Open FlipStudy to start")
                    .font(.callout.weight(.semibold))
            }
        }
    }
}

struct FlipStudyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FlipStudyWidget", provider: StudyProvider()) { entry in
            StudyWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Cards Due")
        .description("How many cards are ready to study, and your streak.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct FlipStudyWidgetBundle: WidgetBundle {
    var body: some Widget {
        FlipStudyWidget()
    }
}
