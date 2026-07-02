import Foundation
import AVFoundation
import NaturalLanguage

/// Speaks a card's answer aloud in the language it's actually written in.
///
/// Cards don't store a language, and a deck can mix languages, so the language
/// is detected from the text itself (Natural Language framework) right before
/// speaking. That means the *translation* side is read in Italian/Spanish/etc.
/// rather than in an English voice, which is the whole point of hearing it.
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    /// True while audio is playing, so the UI can show a stop/active state.
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speak `text`, choosing a voice for the language the text is written in.
    /// An optional `hint` (the deck/card's known target language) is used when
    /// detection is uncertain — e.g. very short answers like a single word.
    func speak(_ text: String, hint: AnswerLanguage? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Tapping again while speaking stops playback.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        configureAudioSession()

        let code = Self.voiceLanguage(for: trimmed, hint: hint)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = Self.bestVoice(for: code)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    // MARK: - Voice selection

    /// Detect the BCP-47 language of `text`, falling back to the hint (or English)
    /// when the recognizer isn't confident on a short string.
    private static func voiceLanguage(for text: String, hint: AnswerLanguage?) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        if let language = recognizer.dominantLanguage,
           let top = recognizer.languageHypotheses(withMaximum: 1)[language],
           top >= 0.65 {
            return regionQualified(language.rawValue)
        }
        if let hint, hint != .english {
            return regionQualified(hint.code)
        }
        return regionQualified(recognizer.dominantLanguage?.rawValue ?? "en")
    }

    /// AVSpeechSynthesisVoice wants a region-qualified code (e.g. "it-IT"), so
    /// map a bare or script-tagged language code to a sensible default region.
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

    /// Prefer an exact match; otherwise any voice whose language shares the base
    /// code; otherwise let the system pick its default for that code.
    private static func bestVoice(for code: String) -> AVSpeechSynthesisVoice? {
        if let exact = AVSpeechSynthesisVoice(language: code) {
            return exact
        }
        let base = code.split(separator: "-").first.map(String.init) ?? code
        return AVSpeechSynthesisVoice.speechVoices()
            .first { $0.language.hasPrefix(base) }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Respect the silent switch but mix politely; ignore failures — worst
        // case the utterance just doesn't play, which isn't worth surfacing.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
