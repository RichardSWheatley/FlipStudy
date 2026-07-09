import Foundation
import Speech
import AVFoundation
import NaturalLanguage

/// Listens to the microphone and transcribes what the learner says, so a study
/// card can be answered *out loud* instead of flipped. Recognition runs
/// on-device when the language supports it — no audio leaves the phone.
///
/// A card stores no language, so the language to listen for is detected from the
/// answer text itself (the same trick `SpeechPlayer` uses to pick a voice), with
/// an optional hint for very short answers where detection is unsure.
@MainActor
@Observable
final class SpeechRecognizer {
    /// The best transcript so far while the learner is speaking.
    private(set) var transcript = ""
    /// True while the microphone is live.
    private(set) var isListening = false

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    enum RecognizerError: LocalizedError {
        case notAuthorized
        case micDenied
        case unsupportedLanguage
        case unavailable
        case audio(String)

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "FlipStudy needs Speech Recognition access to check your answer. Turn it on in Settings › FlipStudy."
            case .micDenied:
                return "FlipStudy needs microphone access to hear you. Turn it on in Settings › FlipStudy."
            case .unsupportedLanguage:
                return "Speaking practice isn't available for this language on your device yet. You can still flip and grade yourself."
            case .unavailable:
                return "Speech recognition isn't available right now. Try again in a moment."
            case .audio(let detail):
                return "Couldn't start the microphone: \(detail)"
            }
        }
    }

    // MARK: - Availability

    /// Whether speaking practice can work for a given answer's language, so the
    /// UI can hide the feature instead of offering a button that will fail.
    static func isSupported(forAnswer answer: String, hint: AnswerLanguage?) -> Bool {
        guard let locale = detectLocale(for: answer, hint: hint) else { return false }
        guard let recognizer = SFSpeechRecognizer(locale: locale) else { return false }
        return recognizer.isAvailable
    }

    // MARK: - Listening

    /// Ask for microphone + speech permission, then start transcribing. The
    /// language is chosen from `answer` so we listen in Italian/Spanish/etc.
    func start(expecting answer: String, hint: AnswerLanguage?) async throws {
        guard !isListening else { return }

        guard let locale = Self.detectLocale(for: answer, hint: hint),
              let recognizer = SFSpeechRecognizer(locale: locale) else {
            throw RecognizerError.unsupportedLanguage
        }
        guard recognizer.isAvailable else { throw RecognizerError.unavailable }

        try await requestAuthorization()

        self.recognizer = recognizer
        transcript = ""

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep audio on-device when the language model supports it (private and
        // works offline); fall back to Apple's servers otherwise.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            teardown()
            throw RecognizerError.audio(error.localizedDescription)
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                }
                if error != nil { self.stop() }
            }
        }
    }

    /// Stop listening and return the final transcript.
    @discardableResult
    func stop() -> String {
        guard isListening || task != nil else { return transcript }
        teardown()
        isListening = false
        return transcript
    }

    private func teardown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Authorization

    private func requestAuthorization() async throws {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let speechGranted: Bool
        switch speechStatus {
        case .authorized:
            speechGranted = true
        case .notDetermined:
            speechGranted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        default:
            speechGranted = false
        }
        guard speechGranted else { throw RecognizerError.notAuthorized }

        let micGranted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        guard micGranted else { throw RecognizerError.micDenied }
    }

    // MARK: - Language detection

    /// Detect the answer's language and turn it into a `Locale` for the speech
    /// recognizer, preferring the hint when the text is too short to be sure.
    private static func detectLocale(for text: String, hint: AnswerLanguage?) -> Locale? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        if let language = recognizer.dominantLanguage,
           let top = recognizer.languageHypotheses(withMaximum: 1)[language],
           top >= 0.65 {
            return Locale(identifier: regionQualified(language.rawValue))
        }
        if let hint, hint != .english {
            return Locale(identifier: regionQualified(hint.code))
        }
        if let language = recognizer.dominantLanguage {
            return Locale(identifier: regionQualified(language.rawValue))
        }
        return nil
    }

    /// Map a bare language code to a region-qualified one a recognizer expects.
    private static func regionQualified(_ raw: String) -> String {
        let base = raw.split(separator: "-").first.map(String.init) ?? raw
        switch base {
        case "en": return "en-US"
        case "it": return "it-IT"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "pt": return "pt-BR"
        case "ja": return "ja-JP"
        case "zh": return raw.contains("Hant") ? "zh-TW" : "zh-CN"
        default: return raw.contains("-") ? raw : "\(base)-\(base.uppercased())"
        }
    }

    // MARK: - Grading

    /// How close a spoken answer is to the expected text, from 0 (nothing alike)
    /// to 1 (identical after normalizing). Lenient on purpose: a learner's
    /// pronunciation gets misheard often, so accents, case, and punctuation are
    /// ignored, and a spoken answer that *contains* the expected text counts as a
    /// full match (the recognizer sometimes tacks on extra words).
    static func similarity(spoken: String, expected: String) -> Double {
        let a = normalize(spoken)
        let b = normalize(expected)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        if a.contains(b) || b.contains(a) { return 1 }
        let distance = levenshtein(Array(a), Array(b))
        let longest = max(a.count, b.count)
        return 1 - (Double(distance) / Double(longest))
    }

    /// A spoken answer is "close enough" at this similarity or above.
    static let passThreshold = 0.8

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let stripped = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || $0 == " "
        }
        let collapsed = String(String.UnicodeScalarView(stripped))
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
        return collapsed
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
