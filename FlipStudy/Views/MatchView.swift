import SwiftUI
import SwiftData

/// Matching game: fronts on the left, backs on the right, tap one of each to
/// pair them. It's a warm-up — every pair found counts toward the daily goal,
/// but it doesn't move cards between boxes, since spotting an answer is easier
/// than recalling it.
struct MatchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query private var studyDays: [StudyDay]
    let deck: Deck

    private struct Tile: Identifiable, Equatable {
        enum Side { case front, back }
        let pairID: UUID
        let side: Side
        let text: String
        var id: String { "\(side)-\(pairID)" }
    }

    @State private var pairCount = 0
    @State private var fronts: [Tile] = []
    @State private var backs: [Tile] = []
    @State private var selected: Tile?
    @State private var matched: Set<UUID> = []
    /// The two tiles of a wrong guess, shown red for a moment.
    @State private var wrong: [Tile] = []
    @State private var misses = 0
    @State private var startedAt = Date.now
    @State private var finishedIn: TimeInterval?
    @State private var confettiTrigger = 0

    private var settings: AppSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            Group {
                if let finishedIn {
                    summary(seconds: finishedIn)
                } else {
                    board
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DeckBackdrop(palette: deck.palette))
            .overlay {
                ConfettiView(trigger: confettiTrigger)
                    .ignoresSafeArea()
            }
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if finishedIn == nil {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(matched.count), total: Double(max(pairCount, 1)))
                                .tint(deck.palette.bottom)
                                .frame(width: 110)
                            Text("\(matched.count)/\(pairCount)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(matched.count) of \(pairCount) matched")
                    }
                }
            }
        }
        .tint(deck.palette.bottom)
        .onAppear(perform: newRound)
        .onDisappear { StudyProgress.refresh(context: context, settings: settings) }
        .sensoryFeedback(.success, trigger: matched.count)
        .sensoryFeedback(.error, trigger: misses)
    }

    private var board: some View {
        VStack(spacing: 16) {
            Text("Tap a card on each side to make a pair! 🧩")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 12) {
                column(fronts)
                column(backs)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }

    private func column(_ tiles: [Tile]) -> some View {
        VStack(spacing: 10) {
            ForEach(tiles) { tile in
                tileButton(tile)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Questions are white tiles edged in the deck's colour; answers are
    /// tiles in the colour itself, so the two sides never look alike.
    private func tileButton(_ tile: Tile) -> some View {
        let isMatched = matched.contains(tile.pairID)
        let isWrong = wrong.contains(tile)
        let isSelected = selected == tile
        let palette = deck.palette
        let isAnswer = tile.side == .back
        let fill: AnyShapeStyle = isMatched ? AnyShapeStyle(DeckPalette.lime.gradient)
            : isWrong ? AnyShapeStyle(DeckPalette.berry.gradient)
            : isAnswer ? AnyShapeStyle(palette.gradient)
            : AnyShapeStyle(Color(.systemBackground))
        let textColor: Color = isMatched || isWrong || isAnswer ? .white : palette.ink
        return Button {
            tap(tile)
        } label: {
            Text(tile.text)
                .font(.callout.weight(.bold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, minHeight: 68)
                .padding(.horizontal, 6)
                .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(Color.primary.opacity(0.85))
                                      : isAnswer || isMatched || isWrong ? AnyShapeStyle(Color.clear)
                                      : AnyShapeStyle(palette.top.opacity(0.7)),
                                      lineWidth: isSelected ? 4 : 2.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isMatched {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .padding(5)
                    }
                }
                .shadow(color: palette.bottom.opacity(isSelected ? 0.4 : 0.15), radius: isSelected ? 8 : 4, y: 3)
                .scaleEffect(isSelected ? 1.06 : 1)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(SquishButtonStyle())
        .modifier(ShakeEffect(progress: isWrong ? 1 : 0))
        .animation(.linear(duration: 0.4), value: isWrong)
        .opacity(isMatched ? 0.45 : 1)
        .allowsHitTesting(!isMatched && wrong.isEmpty)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func tap(_ tile: Tile) {
        guard let first = selected else {
            selected = tile
            return
        }
        if first == tile {
            selected = nil
            return
        }
        // Two from the same side: switch the selection rather than guess.
        if first.side == tile.side {
            selected = tile
            return
        }
        selected = nil
        if first.pairID == tile.pairID {
            withAnimation(.easeInOut(duration: 0.25)) { _ = matched.insert(tile.pairID) }
            StudyProgress.recordReview(in: context)
            if matched.count == pairCount {
                withAnimation { finishedIn = Date.now.timeIntervalSince(startedAt) }
                confettiTrigger += 1
            }
        } else {
            misses += 1
            wrong = [first, tile]
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                withAnimation { wrong = [] }
            }
        }
    }

    private func newRound() {
        var rng = SystemRandomNumberGenerator()
        let pairs = QuizBuilder.matchRound(
            from: deck.allCards.map { .init(id: $0.id, front: $0.front, back: $0.back) },
            using: &rng
        )
        pairCount = pairs.count
        fronts = pairs.map { Tile(pairID: $0.id, side: .front, text: $0.front) }.shuffled(using: &rng)
        backs = pairs.map { Tile(pairID: $0.id, side: .back, text: $0.back) }.shuffled(using: &rng)
        selected = nil
        matched = []
        wrong = []
        misses = 0
        startedAt = .now
        finishedIn = nil
    }

    private func summary(seconds: TimeInterval) -> some View {
        let stars = misses == 0 ? 3 : misses <= 2 ? 2 : 1
        return VStack(spacing: 16) {
            Text(misses == 0 ? "🏆" : "🧩")
                .font(.system(size: 76))
            Text(misses == 0 ? "Perfect Match!" : "All Matched!")
                .font(.largeTitle.bold())
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { star in
                    Image(systemName: star <= stars ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(star <= stars ? Color.yellow : Color.gray.opacity(0.4))
                        .shadow(color: star <= stars ? .orange.opacity(0.4) : .clear, radius: 3, y: 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("\(stars) of 3 stars")
            Text(resultLine(seconds: seconds))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Label(StudyProgress.todayLine(studyDays: studyDays,
                                          goal: settings?.dailyGoal ?? AppSettings.defaultDailyGoal),
                  systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    newRound()
                } label: {
                    Label("Play Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ChunkyButtonStyle(deck.palette.gradient))
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            .padding(.horizontal, 40)
            Text("Matching is practice: it counts toward your daily goal but doesn't change when cards come due.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding()
    }

    private func resultLine(seconds: TimeInterval) -> String {
        let time = Duration.seconds(seconds.rounded())
            .formatted(.time(pattern: .minuteSecond))
        let missPart = misses == 0 ? "no misses" : misses == 1 ? "1 miss" : "\(misses) misses"
        return "\(pairCount) pairs in \(time), \(missPart)."
    }
}
