import SwiftUI
import SwiftData

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    let deck: Deck

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var showingBack = false
    @State private var correctCount = 0
    @State private var includeAll = false

    var body: some View {
        NavigationStack {
            Group {
                if deck.cards.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Study",
                        systemImage: "checkmark.circle",
                        description: Text("This deck has no cards yet.")
                    )
                } else if queue.isEmpty {
                    caughtUp
                } else if index >= queue.count {
                    summary
                } else {
                    reviewing(card: queue[index])
                }
            }
            .navigationTitle(deck.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if index < queue.count {
                    ToolbarItem(placement: .principal) {
                        Text("\(min(index + 1, queue.count)) / \(queue.count)")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onAppear(perform: buildQueue)
    }

    private func reviewing(card: Card) -> some View {
        VStack(spacing: 24) {
            Spacer()

            FlipCard(card: card, showingBack: showingBack)
                .onTapGesture {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showingBack.toggle()
                    }
                }

            Spacer()

            if showingBack {
                HStack(spacing: 16) {
                    answerButton(
                        title: "Missed it",
                        systemImage: "xmark",
                        tint: .red,
                        action: { advance(correct: false) }
                    )
                    answerButton(
                        title: "Got it",
                        systemImage: "checkmark",
                        tint: .green,
                        action: { advance(correct: true) }
                    )
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                Text("Tap the card to flip it")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 28)
            }
        }
        .padding()
    }

    private func answerButton(title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private var caughtUp: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("All Caught Up")
                .font(.title2.bold())
            Text(nextDueMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    includeAll = true
                    buildQueue()
                } label: {
                    Label("Study All Anyway", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private var nextDueMessage: String {
        guard let next = deck.cards.compactMap(\.nextDue).min() else {
            return "Nothing is due right now."
        }
        let formatted = next.formatted(.relative(presentation: .named))
        return "No cards are due. The next one is ready \(formatted)."
    }

    private var summary: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Session Complete")
                .font(.title2.bold())
            Text("You knew \(correctCount) of \(queue.count).")
                .font(.body)
                .foregroundStyle(.secondary)
            VStack(spacing: 12) {
                Button {
                    buildQueue()
                } label: {
                    Label("Study Again", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 8)
            .padding(.horizontal, 40)
        }
        .padding()
    }

    private func advance(correct: Bool) {
        guard index < queue.count else { return }
        let card = queue[index]
        if correct {
            card.markCorrect()
            correctCount += 1
        } else {
            card.markIncorrect()
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            showingBack = false
            index += 1
        }
    }

    private func buildQueue() {
        // Study only cards that are due, unless the user opted to drill the
        // whole deck. Lower Leitner boxes first (those need the most practice).
        let pool = includeAll ? deck.cards : deck.cards.filter(\.isDue)
        queue = pool.sorted {
            $0.leitnerBox != $1.leitnerBox ? $0.leitnerBox < $1.leitnerBox : $0.front < $1.front
        }
        index = 0
        showingBack = false
        correctCount = 0
    }
}

private struct FlipCard: View {
    let card: Card
    let showingBack: Bool

    var body: some View {
        ZStack {
            face(text: card.front, label: "FRONT", filled: false)
                .opacity(showingBack ? 0 : 1)
            face(text: card.back, label: "BACK", filled: true)
                .opacity(showingBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity)
        .frame(height: 320)
    }

    private func face(text: String, label: String, filled: Bool) -> some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(filled ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.background))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
            .overlay {
                VStack(spacing: 16) {
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(text)
                        .font(.system(size: 34, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(6)
                        .minimumScaleFactor(0.35)
                }
                .padding(28)
            }
            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }
}
