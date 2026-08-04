# FlipStudy — Acceptance Plan

*Living document. The scope sections below describe the Pro release (1.3); the
criteria table grows as later releases add behavior, with each criterion tagged
by the release that introduced it.*

## Releases

| Version | Build | State | What it added |
|---|---|---|---|
| 1.3 | 4 | Approved, ready for distribution | The Pro release: $0.99 purchase gating on-device AI, two-mode Scan a Page, `.flipstudy` deck sharing, per-engine cloud keys. Criteria 1–22. |
| 1.4 | 9 | Prepare for submission (awaiting IAP review screenshot) | The scan quality release: paired-vocabulary pages used verbatim, multi-language OCR, wrapped-line rejoining, per-capture text replacement, 24-card cap. Criteria 23–30. |
| 1.5 | 10 | In development | Draft cards are checked before the deck is made and anything doubtful is flagged in the preview. Criteria 31–33. |

## Purpose

Ship the Pro release: a $0.99 one-time FlipStudy Pro purchase gating the
on-device AI features, a smarter Scan a Page with two modes, deck sharing via
`.flipstudy` files, and per-engine cloud translation keys — while keeping the
app local-only, account-free, and kid-safe.

## What 1.3 must do

- Gate on-device AI (Type a Subject, AI page reading in Scan a Page) behind
  FlipStudy Pro, a non-consumable (`com.flipstudy.app.pro`) verified from
  StoreKit's on-device entitlements so ownership works offline. Restore
  Purchase lives in Settings.
- Scan a Page offers two modes: **Questions & answers** (AI extractor for Pro,
  `CardGenerator` line splitter for everyone else) and **Vocabulary to
  translate** (AI term tidying for Pro, `tidyTerm`-guarded line parsing
  otherwise). The mode is auto-detected from the OCR text's shape, and the
  answer language is inferred from the deck title ("Italian Vocab" → Italian).
- Share any deck as a `.flipstudy` JSON file (versioned, `formatVersion` 1)
  from Deck Detail; add one from Home via the file picker with a preview and
  explicit confirm. Import always creates a fresh copy — never a merge.
- Keep one cloud translation API key per engine (Google, Microsoft) in the
  Keychain, migrating the pre-1.2 shared key once. Cloud engines stay behind
  the multiplication parent gate; Microsoft sends the region header.

## What 1.3 must NOT do

- **No accounts, no server.** Entitlement is the StoreKit receipt; sharing is
  a file handed over AirDrop/Messages/Files.
- **No network for core flows.** OCR, AI generation, Apple translation, study,
  and sharing all run on-device. Only the opt-in cloud translators (parent
  gate + the parent's own key) touch the network.
- **The Debug dev unlock never ships.** `developerForcesPro` lives inside
  `#if DEBUG` in `ProStore` and is compiled out of Release; App Store
  customers must go through the purchase.
- **No silent AI fallback for Pro users.** When a Pro user's model can't run,
  Scan a Page shows `AICardGenerator.unavailableReason` (device ineligible /
  Apple Intelligence off / model downloading) instead of quietly producing
  splitter cards.
- **Auto-detection never overrides the user.** An explicit page-kind or
  language pick sticks; title inference and shape detection only fill gaps,
  and English is never inferred from a title.

## Acceptance criteria

| # | Criterion (verifiable behavior) | Proven by |
|---|---|---|
| 1 | `CardGenerator.cards(from:)` splits "Term: definition" / "Term — definition" / tab lines into front/back, drops lines under 3 characters, and leaves the back empty when no separator is found | `FlipStudyTests/CardGeneratorTests.swift` |
| 2 | The first separator found in a line wins, and a line whose separator yields an empty front falls back to whole-line front | `FlipStudyTests/CardGeneratorTests.swift` |
| 3 | `AICardGenerator.tidyTerm` strips list numbering ("3.") and bullet punctuation, and rejects single characters, letterless strings, and status-bar clock times like "9:41" | `FlipStudyTests/VocabTermCleaningTests.swift` |
| 4 | `PhotoDeckView.vocabItems(from:)` produces one cleaned item per useful line, deduplicated case-insensitively, using the same `tidyTerm` guard as the AI path | `FlipStudyTests/VocabTermCleaningTests.swift` |
| 5 | `PhotoDeckView.detectPageKind` returns `.questions` for text with two or more question signals (question marks, "Answer:" lines, "A)" choices) and `.vocabulary` for pages of mostly short lines | `FlipStudyTests/PageKindDetectionTests.swift` |
| 6 | Long prose without question signals still detects as `.questions` (AI extraction reads it best), and empty text defaults to `.questions` | `FlipStudyTests/PageKindDetectionTests.swift` |
| 7 | A `SharedDeck` snapshot round-trips through `DeckTransfer.encode`/`decode` preserving title, subject, and card order | `FlipStudyTests/DeckTransferTests.swift` |
| 8 | `DeckTransfer.decode` throws `notADeck` for non-deck data and `tooNew` for a `formatVersion` above 1, each with a kid-readable message | `FlipStudyTests/DeckTransferTests.swift` |
| 9 | `AnswerLanguage.named(in:)` finds a target language named anywhere in a title, never returns `.english`, and returns nil when no language is named | `FlipStudyTests/AnswerLanguageTests.swift` |
| 10 | Each `AnswerLanguage` maps to its correct BCP-47 code and only non-English values report `isTranslation` | `FlipStudyTests/AnswerLanguageTests.swift` |
| 11 | Without Pro, Home shows "Type a Subject (Pro)" and tapping it opens the paywall instead of the generator; after purchase (StoreKit config `FlipStudy.storekit`) the generator opens directly | simulator scenario |
| 12 | Without Pro, Q&A scanning still produces splitter cards, and the "Read pages with AI" upsell appears only on AI-eligible hardware | simulator scenario |
| 13 | For a Pro user whose model can't run, Scan a Page shows the orange unavailable-reason banner naming why, and cards still generate via the fallback | simulator scenario |
| 14 | Typing a title containing "Italian" flips the scan translation language to Italian, but never after the user has picked a language by hand | simulator scenario |
| 15 | Switching page kind after a scan regenerates the cards for the new mode without re-scanning | simulator scenario |
| 16 | Share Deck exports a `.flipstudy` file whose title survives filename sanitizing; Add a Shared Deck previews it and only inserts a new deck (source `.shared`) on confirm | simulator scenario |
| 17 | Enabling a cloud engine requires passing the multiplication parent gate; a wrong answer re-rolls the problem, and turning Cloud AI off reverts the engine to Apple | simulator scenario |
| 18 | Switching the engine picker swaps the key field to that engine's own Keychain slot — a Microsoft key is never shown or sent under Google | simulator scenario |
| 19 | Test Connection with a valid Microsoft key + region reports the translated "Hello"; a missing region surfaces the parsed 401 detail, not a bare status | on-device |
| 20 | Purchase, Restore Purchase, and Ask-to-Buy pending states resolve correctly against the real App Store sandbox | on-device |
| 21 | On-device AI generation (Type a Subject, AI page reading, vocab tidying) runs with the network off — airplane mode — proving the core flows are local | on-device |
| 22 | A Release/TestFlight build does not auto-unlock Pro (the Debug developer unlock is compiled out) | on-device |
| 23 | A page that already pairs terms with translations ("* Good Morning - Buongiorno") becomes cards from the page's own pairs, verbatim — bullets stripped, nothing generated or re-translated, and the backs' language is recognized (e.g. Italian) so the picker reflects it | `FlipStudyTests/VocabPairDetectorTests.swift` |
| 24 | A single splittable line inside a plain word list does not flip the page into paired mode (majority rule), and pair splitting requires real words on both sides | `FlipStudyTests/VocabPairDetectorTests.swift` |
| 25 | Each new capture replaces the recognized text (no accumulation from previous photos), and no-letter OCR junk (clock times, lone symbols) never reaches the recognized-text box | `FlipStudyTests/VocabPairDetectorTests.swift` (`cleanedOCRLines`) + simulator scenario |
| 26 | The line splitter strips leading list bullets before splitting, without eating leading hyphens that are part of a word | `FlipStudyTests/CardGeneratorTests.swift` |
| 27 | OCR recognizes every language the app can put on a card (en/it/es/fr/de/pt/ja/zh), so a bilingual page is read in its own languages instead of English-corrected into nonsense | on-device (scan an English–Italian list; Italian words come back spelled correctly) |
| 28 | A sentence that wraps across visual lines is rejoined into one block before the extractor sees it, so questions arrive whole rather than as fragments | `FlipStudyTests/TextLayoutTests.swift` |
| 29 | Rejoining never glues separate entries together: a page of uniformly short lines (a vocabulary list) keeps one entry per line, and terminal punctuation or a paragraph gap always ends a block | `FlipStudyTests/TextLayoutTests.swift` |
| 30 | A scanned page yields up to 24 cards rather than being silently truncated at 12 | on-device (scan a dense worksheet; card count reflects the page) |

Every criterion above is checkable; none is a vision statement. Rows 1–10 are
deterministic unit tests in `FlipStudyTests`; simulator scenarios run in the
1.3 release pass; on-device rows run on the physical iPhone before submission.
| 31 | Every drafted card is checked before the deck is created, and anything doubtful is flagged in the preview with a plain-English reason rather than dropped silently | `FlipStudyTests/CardVerifierTests.swift` |
| 32 | The check catches an empty back, the same text on both sides, a repeated front, a back that was never translated into the chosen language, text cut off mid-thought, and a paragraph used as a card front | `FlipStudyTests/CardVerifierTests.swift` |
| 33 | A card can be swiped away in the preview, and all flagged cards can be removed in one action | simulator scenario |
