import SwiftUI
import SwiftData

struct StudyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [AppSettings]
    @Query private var studyDays: [StudyDay]
    let deck: Deck
    var mode: StudyMode = .flashcards

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

    // Type It: the typed answer, and its grade once checked.
    @State private var typed = ""
    @State private var typedResult: AnswerCheck.Result?
    @FocusState private var answerFocused: Bool

    // Quiz: this card's choices, and the one picked.
    @State private var choices: [String] = []
    @State private var picked: String?

    // Explain This Card (FlipStudy Cloud).
    @State private var explainingCard: Card?
    @State private var explanations: [String: CardExplanation] = [:]

    // Cheering: a quick bubble after each card, confetti when a session ends.
    @State private var cheer: String?
    @State private var confettiTrigger = 0

    var body: some View {
        NavigationStack {
            Group {
                if deck.allCards.isEmpty {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DeckBackdrop(palette: deck.palette))
            .overlay(alignment: .top) {
                if let cheer {
                    Text(cheer)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 10)
                        .background(deck.palette.gradient, in: Capsule())
                        .shadow(color: deck.palette.bottom.opacity(0.4), radius: 8, y: 4)
                        .padding(.top, 6)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
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
                if index < queue.count {
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 8) {
                            ProgressView(value: Double(index), total: Double(max(queue.count, 1)))
                                .tint(deck.palette.bottom)
                                .frame(width: 110)
                            Text("\(min(index + 1, queue.count))/\(queue.count)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Card \(min(index + 1, queue.count)) of \(queue.count)")
                    }
                }
                if index < queue.count && mode == .flashcards {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            recognizer.stop()
                            resetSpeakState()
                            withAnimation { speakMode.toggle() }
                        } label: {
                            Image(systemName: speakMode ? "mic.fill" : "mic.slash")
                        }
                        .tint(speakMode ? deck.palette.bottom : .secondary)
                        .accessibilityLabel(speakMode ? "Speaking practice on" : "Speaking practice off")
                    }
                }
            }
        }
        .tint(deck.palette.bottom)
        .onAppear(perform: buildQueue)
        // Studying just changed what's due: bring the widget and the next
        // reminder up to date as the session closes.
        .onDisappear { StudyProgress.refresh(context: context, settings: settings) }
        .sheet(isPresented: $showingAddCard, onDismiss: buildQueue) {
            CardEditorView(deck: deck, card: nil)
        }
        .sheet(item: $explainingCard) { card in
            ExplainCardView(front: card.front, back: card.back,
                            subject: deck.subject.isEmpty ? deck.title : deck.subject,
                            cache: $explanations)
        }
    }

    /// Explaining sends the card to FlipStudy Cloud, so it's offered only when
    /// the cloud engine is the one in use — never to someone who chose to
    /// keep their cards on the device.
    private var canExplain: Bool { CardEngine.active(for: settings) == .cloud }

    @ViewBuilder
    private func explainButton(for card: Card) -> some View {
        if canExplain {
            Button {
                speech.stop()
                explainingCard = card
            } label: {
                Label("Explain", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(deck.palette.bottom)
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
        StudyProgress.todayLine(studyDays: studyDays, goal: settings?.dailyGoal ?? AppSettings.defaultDailyGoal)
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

    @ViewBuilder
    private func reviewing(card: Card) -> some View {
        switch mode {
        case .typeAnswer: typing(card: card)
        case .multipleChoice: quiz(card: card)
        case .flashcards, .match: flipping(card: card)
        }
    }

    private func flipping(card: Card) -> some View {
        VStack(spacing: 24) {
            Spacer()

            FlipCard(card: card, showingBack: showingBack, palette: deck.palette, emoji: deck.displayEmoji)
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

                    HStack(spacing: 12) {
                        listenButton(for: card)
                        explainButton(for: card)
                    }

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

    /// Type It: the front, a box for the answer, then the verdict with the
    /// card flipped so the right answer is always shown.
    private func typing(card: Card) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            FlipCard(card: card, showingBack: showingBack, palette: deck.palette, emoji: deck.displayEmoji, height: 220)
            Spacer(minLength: 0)
            if let result = typedResult {
                VStack(spacing: 16) {
                    typedVerdict(result, card: card)
                    explainButton(for: card)
                    HStack(spacing: 16) {
                        if !result.isRight {
                            // Typed answers can be right in other words; the
                            // learner gets the last say, as with flipping.
                            Button {
                                advance(correct: true)
                            } label: {
                                Text("I Was Right")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.bordered)
                        }
                        answerButton(title: "Next", systemImage: "arrow.right",
                                     tint: .accentColor) { advance(correct: result.isRight) }
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: 12) {
                    TextField("Type the answer", text: $typed)
                        .font(.title3)
                        .padding(16)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(deck.palette.top.opacity(0.7), lineWidth: 2.5)
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .focused($answerFocused)
                        .onSubmit { checkTyped(card: card) }
                    HStack(spacing: 16) {
                        Button {
                            typed = ""
                            checkTyped(card: card)
                        } label: {
                            Text("Show Me")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.bordered)
                        answerButton(title: "Check", systemImage: "checkmark",
                                     tint: .accentColor) { checkTyped(card: card) }
                            .disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .padding()
        .onAppear { answerFocused = true }
    }

    private func typedVerdict(_ result: AnswerCheck.Result, card: Card) -> some View {
        VStack(spacing: 4) {
            switch result {
            case .correct:
                Label("Correct!", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .close:
                Label("Almost — check the spelling", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .wrong:
                Label(typed.isEmpty ? "Here's the answer" : "Not quite",
                      systemImage: typed.isEmpty ? "eye" : "xmark.circle.fill")
                    .foregroundStyle(typed.isEmpty ? Color.secondary : Color.red)
            }
            if !typed.isEmpty && result != .correct {
                Text("You typed: \(typed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.subheadline.weight(.semibold))
    }

    private func checkTyped(card: Card) {
        typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        answerFocused = false
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
            typedResult = AnswerCheck.grade(typed: typed, expected: card.back)
            showingBack = true
        }
    }

    /// Quiz: the front and a few backs to choose from. Picking one shows which
    /// was right straight away; Next moves on.
    private func quiz(card: Card) -> some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)
            FlipCard(card: card, showingBack: false, palette: deck.palette, emoji: deck.displayEmoji, height: 200)
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                ForEach(choices, id: \.self) { choice in
                    choiceButton(choice, card: card)
                }
            }
            if let picked {
                VStack(spacing: 12) {
                    explainButton(for: card)
                    answerButton(title: "Next", systemImage: "arrow.right", tint: .accentColor) {
                        advance(correct: isAnswer(picked, for: card))
                    }
                }
                .transition(.opacity)
            }
        }
        .padding()
    }

    private func choiceButton(_ choice: String, card: Card) -> some View {
        let isRight = isAnswer(choice, for: card)
        let revealed = picked != nil
        let isPickedWrong = revealed && choice == picked && !isRight
        let fill: AnyShapeStyle = {
            guard revealed else { return AnyShapeStyle(Color(.systemBackground)) }
            if isRight { return AnyShapeStyle(DeckPalette.lime.gradient) }
            if isPickedWrong { return AnyShapeStyle(DeckPalette.berry.gradient) }
            return AnyShapeStyle(Color.gray.opacity(0.12))
        }()
        let icon: String? = !revealed ? nil : isRight ? "checkmark.circle.fill" : isPickedWrong ? "xmark.circle.fill" : nil
        return Button {
            guard picked == nil else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { picked = choice }
        } label: {
            HStack(spacing: 10) {
                Text(choice)
                    .font(.body.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if let icon {
                    Image(systemName: icon)
                        .font(.title3)
                }
            }
            .foregroundStyle(revealed && (isRight || isPickedWrong) ? Color.white : revealed ? Color.secondary : deck.palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(fill, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(deck.palette.top.opacity(revealed ? 0 : 0.6), lineWidth: 2.5)
            }
            .scaleEffect(revealed && isRight ? 1.03 : 1)
        }
        .buttonStyle(SquishButtonStyle())
        .allowsHitTesting(!revealed)
        .sensoryFeedback(trigger: picked) { _, new in
            guard new == choice else { return nil }
            return isRight ? .success : .error
        }
    }

    private func isAnswer(_ choice: String, for card: Card) -> Bool {
        AnswerCheck.fold(choice) == AnswerCheck.fold(card.back)
    }

    /// Clear the per-card Type It and Quiz state, and deal the next card's
    /// choices from the whole deck (not just what's due).
    private func prepareCard() {
        typed = ""
        typedResult = nil
        picked = nil
        guard mode == .multipleChoice, index < queue.count else { return }
        var rng = SystemRandomNumberGenerator()
        choices = QuizBuilder.choices(answer: queue[index].back,
                                      from: deck.allCards.map(\.back), using: &rng)
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
            .tint(recognizer.isListening ? .red : deck.palette.bottom)

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
                .font(.title3.bold())
        }
        .buttonStyle(ChunkyButtonStyle(answerFill(tint)))
    }

    /// Missed it is berry, Got it is lime, anything else wears the deck's colour.
    private func answerFill(_ tint: Color) -> AnyShapeStyle {
        if tint == .red { return AnyShapeStyle(DeckPalette.berry.gradient) }
        if tint == .green { return AnyShapeStyle(DeckPalette.lime.gradient) }
        return AnyShapeStyle(deck.palette.gradient)
    }

    /// A bubble of praise (or encouragement) that pops up and fades.
    private func showCheer(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { cheer = text }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if cheer == text {
                withAnimation(.easeOut(duration: 0.25)) { cheer = nil }
            }
        }
    }

    private var caughtUp: some View {
        VStack(spacing: 16) {
            Text("😎")
                .font(.system(size: 72))
            Text("All Caught Up!")
                .font(.largeTitle.bold())
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
                }
                .buttonStyle(ChunkyButtonStyle(deck.palette.gradient))

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
        guard let next = deck.allCards.compactMap(\.nextDue).min() else {
            return "Nothing is due right now."
        }
        let formatted = next.formatted(.relative(presentation: .named))
        return "No cards are due. The next one is ready \(formatted)."
    }

    private var summary: some View {
        let finish = Cheer.finish(correct: correctCount, total: queue.count)
        let stars = Cheer.stars(correct: correctCount, total: queue.count)
        return VStack(spacing: 16) {
            Text(finish.emoji)
                .font(.system(size: 76))
            Text(finish.title)
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
                }
                .buttonStyle(ChunkyButtonStyle(deck.palette.gradient))

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
            prepareCard()
        }
        if index >= queue.count {
            confettiTrigger += 1
        } else {
            showCheer((correct ? Cheer.correct : Cheer.missed).randomElement() ?? "")
        }
        if mode == .typeAnswer { answerFocused = index < queue.count }
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
        let pool = includeAll ? deck.allCards : deck.allCards.filter(\.isDue)
        queue = pool.sorted {
            $0.leitnerBox != $1.leitnerBox ? $0.leitnerBox < $1.leitnerBox : $0.front < $1.front
        }
        index = 0
        showingBack = false
        correctCount = 0
        prepareCard()
    }
}

private struct FlipCard: View {
    let card: Card
    let showingBack: Bool
    var palette: DeckPalette = .ocean
    var emoji: String = ""
    var height: CGFloat = 320

    var body: some View {
        ZStack {
            front
                .opacity(showingBack ? 0 : 1)
            back
                .opacity(showingBack ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .rotation3DEffect(.degrees(showingBack ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    /// The question: a white card edged in the deck's colour.
    private var front: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(palette.gradient, lineWidth: 4)
            }
            .overlay(alignment: .topLeading) {
                Text(emoji)
                    .font(.title)
                    .padding(16)
            }
            .overlay {
                VStack(spacing: 14) {
                    Text("QUESTION")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(palette.ink)
                        .tracking(1.5)
                    faceText(card.front)
                        .foregroundStyle(.primary)
                }
                .padding(28)
            }
            .shadow(color: palette.bottom.opacity(0.18), radius: 14, y: 6)
    }

    /// The answer: the deck's colour, full strength.
    private var back: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(palette.gradient)
            .overlay(alignment: .topLeading) {
                Text("💡")
                    .font(.title)
                    .padding(16)
            }
            .overlay {
                VStack(spacing: 14) {
                    Text("ANSWER")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .opacity(0.85)
                    faceText(card.back)
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                .padding(28)
            }
            .shadow(color: palette.bottom.opacity(0.3), radius: 14, y: 6)
    }

    private func faceText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .lineLimit(6)
            .minimumScaleFactor(0.35)
    }
}
