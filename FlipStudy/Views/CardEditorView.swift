import SwiftUI
import SwiftData
import Translation

/// Create or edit a single card. When creating, the user types the front in
/// English and can either type the back themselves or let the translator fill
/// it in — the same on-device (or cloud) engine used for whole decks, applied
/// to one card at a time.
struct CardEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [AppSettings]

    let deck: Deck
    /// nil means we're creating a new card.
    let card: Card?

    @State private var front = ""
    @State private var back = ""

    /// Language the translator should render the back in.
    @State private var targetLanguage: AnswerLanguage = .italian
    @State private var isTranslating = false
    @State private var errorMessage: String?

    // Apple's translator vends its session through `.translationTask`; a config
    // is set to kick a translation off and invalidated to re-run the same pair.
    @State private var translateConfig: TranslationSession.Configuration?
    @State private var lastTarget: AnswerLanguage?

    private let sourceLanguage = Locale.Language(identifier: "en")

    private var settings: AppSettings? { settingsList.first }
    private var provider: TranslationProvider { settings?.translationProvider ?? .apple }

    private var isEditing: Bool { card != nil }

    private var trimmedFront: String {
        front.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedFront.isEmpty &&
        !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canTranslate: Bool {
        !trimmedFront.isEmpty && !isTranslating && targetLanguage != .english
    }

    /// Languages we can translate the English front into (English itself is not
    /// a translation target).
    private var translationLanguages: [AnswerLanguage] {
        AnswerLanguage.allCases.filter { $0 != .english }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Front (English)") {
                    TextField("Question or term", text: $front, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("Back") {
                    TextField("Answer or translation", text: $back, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Picker("Translate into", selection: $targetLanguage) {
                        ForEach(translationLanguages) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    Button {
                        translate()
                    } label: {
                        if isTranslating {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Translating…")
                            }
                        } else {
                            Label("Fill Back with AI Translation", systemImage: "sparkles")
                        }
                    }
                    .disabled(!canTranslate)
                } footer: {
                    Text(translateFootnote)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .translationTask(translateConfig) { session in
                await runAppleTranslation(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let card {
                    front = card.front
                    back = card.back
                }
            }
        }
    }

    private var translateFootnote: String {
        if provider.isCloud {
            return "Type the English side above, then \(provider.label) translates it into \(targetLanguage.label). You can also just type the back yourself."
        }
        return "Type the English side above, then Apple translates it into \(targetLanguage.label) on your device — free and private. You can also just type the back yourself."
    }

    // MARK: - Translation

    private func translate() {
        errorMessage = nil
        isTranslating = true
        if provider.isCloud {
            Task { await runCloudTranslation() }
        } else {
            triggerAppleTranslation()
        }
    }

    private func triggerAppleTranslation() {
        if lastTarget == targetLanguage, translateConfig != nil {
            // Same language pair as last time: invalidate to re-run the task.
            translateConfig?.invalidate()
        } else {
            translateConfig = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage.locale)
            lastTarget = targetLanguage
        }
    }

    private func runAppleTranslation(session: TranslationSession) async {
        guard !trimmedFront.isEmpty else {
            isTranslating = false
            return
        }
        do {
            let results = try await AppleTranslator(session: session).translate([trimmedFront])
            if let first = results.first, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                back = first
            } else {
                errorMessage = "Couldn't translate that. Try rewording the front, or type the back yourself."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isTranslating = false
    }

    private func runCloudTranslation() async {
        do {
            guard let settings, settings.cloudAIEnabled else {
                throw CloudTranslationError.notEnabled
            }
            let key = CloudTranslationKey.read()
            let results = try await CloudTranslator(provider: provider, apiKey: key,
                                                    source: .english, target: targetLanguage)
                .translate([trimmedFront])
            if let first = results.first, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                back = first
            } else {
                errorMessage = "Couldn't translate that. Try rewording the front, or type the back yourself."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isTranslating = false
    }

    // MARK: - Persistence

    private func save() {
        let f = front.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = back.trimmingCharacters(in: .whitespacesAndNewlines)
        if let card {
            card.front = f
            card.back = b
        } else {
            let newCard = Card(front: f, back: b)
            newCard.deck = deck
            context.insert(newCard)
        }
        dismiss()
    }
}
