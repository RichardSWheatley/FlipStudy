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
    @State private var showingAddCard = false
    @State private var speech = SpeechPlayer()
    @State private var reminders = RemindersService()
    @State private var showingReminder = false

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
        .sheet(isPresented: $showingAddCard, onDismiss: buildQueue) {
            CardEditorView(deck: deck, card: nil)
        }
        .sheet(isPresented: $showingReminder) {
            StudyReminderSheet(
                deckTitle: deck.title,
                suggestedDate: suggestedReminderDate,
                service: reminders
            )
        }
    }

    /// A sensible default time for a study reminder: the deck's earliest future
    /// due date if there is one, otherwise tomorrow at 9am.
    private var suggestedReminderDate: Date {
        if let soonest = deck.cards.compactMap(\.nextDue).filter({ $0 > .now }).min() {
            return soonest
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }

    /// Button shown on the finished screens to schedule a study reminder.
    private var remindButton: some View {
        Button {
            showingReminder = true
        } label: {
            Label("Remind Me to Study", systemImage: "bell")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    /// Add-a-card button shown on the "finished" screens so a new card (with
    /// optional AI translation) can be made without leaving the study session.
    private var addCardButton: some View {
        Button {
            showingAddCard = true
        } label: {
            Label("Add a Card", systemImage: "sparkles")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func reviewing(card: Card) -> some View {
        VStack(spacing: 24) {
            Spacer()

            FlipCard(card: card, showingBack: showingBack)
                .onTapGesture {
                    if showingBack { speech.stop() }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showingBack.toggle()
                    }
                }

            Spacer()

            if showingBack {
                VStack(spacing: 16) {
                    listenButton(for: card)

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

    /// Speaker button that reads the answer aloud in its own language (Italian,
    /// Spanish, …) rather than an English voice. Tapping again stops playback.
    private func listenButton(for card: Card) -> some View {
        Button {
            if speech.isSpeaking {
                speech.stop()
            } else {
                speech.speak(card.back)
            }
        } label: {
            Label(
                speech.isSpeaking ? "Stop" : "Listen",
                systemImage: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill"
            )
            .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.bordered)
        .tint(.accentColor)
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

                addCardButton

                remindButton

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

                addCardButton

                remindButton

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
        speech.stop()
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

/// Sheet to schedule a study reminder in the system Reminders app. Picking a
/// time and tapping Set triggers the Reminders permission prompt on first use.
private struct StudyReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    let deckTitle: String
    let suggestedDate: Date
    let service: RemindersService

    @State private var date: Date
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmation: String?

    init(deckTitle: String, suggestedDate: Date, service: RemindersService) {
        self.deckTitle = deckTitle
        self.suggestedDate = suggestedDate
        self.service = service
        _date = State(initialValue: suggestedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let confirmation {
                    Section {
                        Label(confirmation, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section {
                        DatePicker(
                            "Remind me",
                            selection: $date,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    } footer: {
                        Text("Adds a reminder to your Reminders app so you don't forget to study \(deckTitle).")
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }

                    Section {
                        Button(action: save) {
                            HStack {
                                if isSaving { ProgressView() }
                                Text(isSaving ? "Setting…" : "Set Reminder")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle("Study Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(confirmation == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        isSaving = true
        let title = "Study \(deckTitle) in FlipStudy"
        Task {
            do {
                let when = try await service.addStudyReminder(title: title, due: date)
                confirmation = "Reminder set for \(when.formatted(date: .abbreviated, time: .shortened))."
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
