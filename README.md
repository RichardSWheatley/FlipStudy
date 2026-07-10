# FlipStudy

A free, private flashcard app for iPhone. Make a deck by typing a subject,
scanning a page, or adding cards by hand, then study with spaced repetition —
hear answers spoken in their own language, or practice saying them out loud.

Everything that can run on the device does: card generation, translation, text
recognition, and speech all work on-device by default. No account, no tracking,
and nothing leaves your phone unless you opt into a cloud translation engine
with your own API key.

## Features

- **Type a subject** — Apple's on-device model drafts study cards from a plain
  topic. Language decks are translated by Apple's Translation framework so the
  words come from a real translation engine, not the model's guesses.
- **Scan a page** — capture a worksheet, glossary, or textbook page; on-device
  text recognition (Vision) plus the model turn it into cards you review before
  the deck is created.
- **Add cards by hand** — a simple front/back editor, with optional AI
  translation of the answer.
- **Card styles** — single words, phrases & sentences, or **sentence starters**
  (a fixed set of common openers like "I want…", "Can you…", the same basics in
  every language, plus AI-generated extras).
- **Spaced repetition** — a five-box Leitner schedule surfaces due cards first
  and spaces out the ones you know.
- **Hear the answer** — the translation side is read aloud in its own voice
  (Italian, Spanish, …), with the language detected from the text.
- **Speaking practice** — a reverse mode: see the front, say the answer out
  loud, and on-device speech recognition suggests a grade. Grading is lenient
  (accents, case, and punctuation ignored), and you always make the final call.
- **Study reminders** — schedule a reminder in the system Reminders app so you
  don't forget to come back.

## Requirements

- Xcode with the iOS 26 SDK
- iPhone running iOS 26 or later (iPhone-only)
- Apple Intelligence enabled for on-device AI card generation

## Building

1. Open `FlipStudy.xcodeproj` in Xcode.
2. Select the **FlipStudy** scheme.
3. Choose your iPhone (or a simulator) and run.

On-device AI generation requires a device that supports Apple Intelligence with
it turned on; the rest of the app works without it.

## Project structure

```
FlipStudy/
  FlipStudyApp.swift        App entry point and SwiftData container
  Models/                   SwiftData models
    Card.swift              A flashcard + its Leitner scheduling
    Deck.swift              A deck of cards
    AppSettings.swift       User settings (cloud AI, translation provider)
  Services/
    AICardGenerator.swift   On-device card/concept generation (FoundationModels)
    CardGenerator.swift     Rule-based card splitting (offline, no AI)
    Translator.swift        Apple + optional cloud translation; deck styles
    TextRecognizer.swift    OCR of scanned pages (Vision)
    Speech.swift            Text-to-speech of answers (AVSpeechSynthesizer)
    SpeechRecognizer.swift  Speech-to-text grading for speaking practice
    RemindersService.swift  Study reminders (EventKit)
  Views/
    HomeView.swift          Deck list / home
    CreateDeckView.swift    Create or edit a deck by hand
    TypeSubjectView.swift   Make a deck from a typed topic
    PhotoDeckView.swift     Make a deck from a scanned page
    DocumentScanner.swift   Camera document capture
    DeckDetailView.swift    A deck's cards and study button
    CardEditorView.swift    Add / edit a card
    StudyView.swift         The study session (flip, speak, grade)
    SettingsView.swift      Settings
```

## Privacy

- On-device by default: generation, translation, OCR, speech synthesis, and
  speech recognition run locally where the platform supports it.
- No accounts, no analytics, no third-party tracking.
- Speech recognition prefers on-device processing; for languages that don't
  support it, audio may be processed by Apple's speech service.
- Cloud translation (Google / Microsoft) is optional, off by default, gated
  behind a grown-up check, and uses your own API key stored in the Keychain.

## Tech

Swift 6 · SwiftUI · SwiftData · FoundationModels · Translation · NaturalLanguage
· Vision · AVFoundation · Speech · EventKit
