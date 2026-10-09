import SwiftUI
import SwiftData

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query private var studyDays: [StudyDay]
    let deck: Deck

    @State private var queue: [Card] = []
    @State private var index = 0
    @State private var showingBack = false
    @State private var correctCount = 0
    @State private var includeAll = false
    @State private var showingAddCard = false
    @State private var speech = SpeechPlayer()
    /// Set when someone turns on the daily reminder from here but iOS has
    /// notifications switched off for FlipStudy.
    @State private var reminderBlocked = false
    /// Set once the reminder is turned on from here, so the button gives way
    /// to a confirmation instead of just vanishing.
    @State private var reminderJustSet = false

    // Speaking practice: see the front, say the answer aloud, and let speech
    // recognition suggest a grade. Off by default; a per-session toggle.
    @State private var recognizer = SpeechRecognizer()
    @State private var speakMode = false
    @State private var lastSpokenScore: Double?
    @State private var lastSpokenText = ""
    @State private var speakError: String?

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
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            recognizer.stop()
                            resetSpeakState()
                            withAnimation { speakMode.toggle() }
                        } label: {
                            Image(systemName: speakMode ? "mic.fill" : "mic.slash")
                        }
                        .tint(speakMode ? .accentColor : .secondary)
                        .accessibilityLabel(speakMode ? "Speaking practice on" : "Speaking practice off")
                    }
                }
            }
        }
        .onAppear(perform: buildQueue)
        // Studying just changed what's due: bring the widget and the next
        // reminder up to date as the session closes.
        .onDisappear { StudyProgress.refresh(context: context, settings: settings) }
        .sheet(isPresented: $showingAddCard, onDismiss: buildQueue) {
            CardEditorView(deck: deck, card: nil)
        }
    }

    private var settings: AppSettings? { settingsList.first }

    /// Offered on the finished screens until the daily reminder is on — the
    /// moment someone has just studied is when "remind me tomorrow" makes sense.
    @ViewBuilder
    private var remindButton: some View {
        if reminderBlocked {
            Text("Notifications are off for FlipStudy. Turn them on in the Settings app to get a daily reminder.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if reminderJustSet {
            Label("Reminder set for \(reminderTimeText). Change it in Settings.", systemImage: "bell.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else if !(settings?.reminderEnabled ?? false) {
            Button {
                Task { await turnOnDailyReminder() }
            } label: {
                Label("Remind Me Every Day", systemImage: "bell")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func turnOnDailyReminder() async {
        guard await StudyNotifier.requestPermission() else {
            reminderBlocked = true
            return
        }
        settings?.reminderEnabled = true
        reminderJustSet = true
        StudyProgress.refresh(context: context, settings: settings)
    }

    /// The reminder time as the phone shows times, e.g. "5:00 PM".
    private var reminderTimeText: String {
        let minutes = settings?.reminderMinutes ?? AppSettings.defaultReminderMinutes
        let time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60,
                                         second: 0, of: .now) ?? .now
        return time.formatted(date: .omitted, time: .shortened)
    }

    /// Today's streak and goal, shown when a session ends.
    private var progressLine: String {
        let reviewed = StudyProgress.reviewed(on: .now, in: studyDays)
        let goal = settings?.dailyGoal ?? AppSettings.defaultDailyGoal
        let streak = StudyProgress.currentStreak(studyDays: studyDays.filter { $0.reviewCount > 0 }.map(\.day))
        let goalPart = reviewed >= goal ? "Daily goal met!" : "\(reviewed) of \(goal) cards today."
        return streak > 0 ? "\(goalPart) \(streak)-day streak." : goalPart
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
                    if recognizer.isListening { recognizer.stop() }
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        showingBack.toggle()
                    }
                }

            Spacer()

            if showingBack {
                VStack(spacing: 16) {
                    if let score = lastSpokenScore {
                        spokenResult(score: score)
                    }

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
            } else if speakMode {
                speakingControls(for: card)
                    .transition(.opacity)
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

    /// Front-of-card controls when speaking practice is on: a mic button to say
    /// the answer, the live transcript, and a reminder that tapping the card to
    /// self-grade still works as a fallback.
    private func speakingControls(for card: Card) -> some View {
        VStack(spacing: 12) {
            if let speakError {
                Text(speakError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            if recognizer.isListening {
                Text(recognizer.transcript.isEmpty ? "Listening…" : recognizer.transcript)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }

            Button {
                toggleListening(for: card)
            } label: {
                Label(
                    recognizer.isListening ? "Stop" : "Say the Answer",
                    systemImage: recognizer.isListening ? "stop.circle.fill" : "mic.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(recognizer.isListening ? .red : .accentColor)

            Text("or tap the card to flip and grade yourself")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    /// Banner shown once an answer has been spoken, suggesting whether it matched.
    /// The learner still makes the final call with Missed it / Got it.
    private func spokenResult(score: Double) -> some View {
        let passed = score >= SpeechRecognizer.passThreshold
        return VStack(spacing: 4) {
            Label(
                passed ? "Sounds right!" : "Not quite — your call",
                systemImage: passed ? "checkmark.circle.fill" : "ear"
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(passed ? .green : .orange)

            if !lastSpokenText.isEmpty {
                Text("You said: \(lastSpokenText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
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
            Label(progressLine, systemImage: "flame.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
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
        recognizer.stop()
        resetSpeakState()
        let card = queue[index]
        StudyProgress.recordReview(in: context)
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

    /// Start or stop listening for the spoken answer. Stopping grades what was
    /// heard against the card's back and flips to reveal the answer.
    private func toggleListening(for card: Card) {
        if recognizer.isListening {
            let spoken = recognizer.stop()
            lastSpokenText = spoken
            lastSpokenScore = SpeechRecognizer.similarity(spoken: spoken, expected: card.back)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                showingBack = true
            }
        } else {
            speech.stop()
            speakError = nil
            lastSpokenScore = nil
            lastSpokenText = ""
            Task {
                do {
                    try await recognizer.start(expecting: card.back, hint: nil)
                } catch {
                    speakError = error.localizedDescription
                }
            }
        }
    }

    /// Clear the spoken-answer state so nothing carries over between cards.
    private func resetSpeakState() {
        lastSpokenScore = nil
        lastSpokenText = ""
        speakError = nil
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
