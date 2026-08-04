# FlipStudy Test Plan — the three layers

*Living document. Every release runs all three layers; the record at the bottom
says when each last ran and what happened.*

FlipStudy's quality gate has three layers, cheapest first:

| Layer | What it proves | How it runs | When |
|---|---|---|---|
| 1. Unit tests (`FlipStudyTests`) | Core logic honors its contract (cleaning, detection, generation, transfer) | `xcodebuild test` / ⌘U | Every change |
| 2. Simulator scenarios (this file, §2) | The *running app* does the right thing end-to-end | Claude drives the sim UI, screenshots each step | Every release + after scan/transfer changes |
| 3. On-device pass (§3) | Real camera, real Apple Intelligence, real StoreKit | Richard follows the script on the physical iPhone | Every release |

Rule of thumb: **a bug found on the phone means a missing case in layers 1–2.**
When one is found, add it *down* the stack (unit test if it's logic, scenario if
it's integration) before fixing it.

---

## 1. Unit tests

```bash
cd ~/code/FlipStudy
xcodebuild test -project FlipStudy.xcodeproj -scheme FlipStudy -destination 'platform=iOS Simulator,name=iPhone 17'
```

- `FlipStudyTests/VocabTermCleaningTests.swift` — scanned vocab terms are cleaned of numbering, bullets, and stray punctuation before they become card fronts.
- `FlipStudyTests/PageKindDetectionTests.swift` — a scanned page is correctly classified (Q&A page vs vocab list vs plain notes), which decides the generation path.
- `FlipStudyTests/CardGeneratorTests.swift` — the fallback line splitter turns raw scanned text into the expected front/back card pairs.
- `FlipStudyTests/DeckTransferTests.swift` — a deck encodes to `.flipstudy` and decodes back with nothing lost or reordered (the share/import round-trip).
- `FlipStudyTests/AnswerLanguageTests.swift` — the answer/translation language for vocab card backs is chosen correctly from the deck and device settings.

Definition of done for any logic change: new/changed behavior has a test here,
and the suite is green.

## 2. Simulator scenario suite (production-style, end-to-end)

Each scenario runs against the **running app** in the iPhone 17 simulator.
Screenshot each verification step.

### S1 — Blank deck + first card
| Step | Action | Must show |
|---|---|---|
| a | New Deck → blank deck, name it "Science" | deck appears on the shelf with its name |
| b | Add a card: front "What is H2O?", back "Water" | card count is 1; flipping the card shows the back |

Screenshot checkpoint: the shelf with the new deck, and the card mid-study showing the back.

### S2 — Scan flow via New Deck menu
| Step | Action | Must show |
|---|---|---|
| a | New Deck → Scan a Page | camera/scan UI opens (photo-library fallback acceptable in sim) |
| b | Provide a page image with Q&A lines | preview lists generated cards before anything is saved |
| c | Confirm | deck exists with the previewed cards |

Screenshot checkpoint: the card preview sheet.
Sim caveat: Apple Intelligence is unavailable in the simulator, so this always
exercises the **line-splitter fallback**, never the AI path (that's §3).

### S3 — Import a shared `.flipstudy` file
| Step | Action | Must show |
|---|---|---|
| a | Open a known-good `.flipstudy` file into the app | import preview shows deck name and card count |
| b | Confirm import | deck appears on the shelf; spot-check two cards |

Screenshot checkpoint: the import preview.

### S4 — Persistence across force-quit
After S1 and S3: force-quit the app, relaunch → decks, cards, and study
progress are all still present. Screenshot checkpoint: the shelf after relaunch.

### What the simulator cannot cover (do not file as bugs)
- **AI card generation** — the Apple Intelligence model is unavailable in the
  simulator, so scans always fall back to the line splitter.
- **StoreKit purchases** — need the `FlipStudy.storekit` configuration attached
  via an Xcode Run, or a sandbox account on a real device; a bare sim launch
  shows no products.

## 3. On-device pass (before every release)

On the physical iPhone:

1. **Scan a real Q&A page with AI** — cards come from the model, not the
   splitter (answers paraphrased/cleaned, not raw line pairs).
2. **Scan a vocab list** — backs come out translated into the deck's answer
   language.
3. **Purchases** — sandbox purchase completes; Restore Purchase restores it.
4. **Share round-trip** — share a deck to Files, then re-import that
   `.flipstudy` file and verify the cards.
5. **Fresh install** — delete the app, reinstall, confirm permission prompts
   (camera/photos) show the kid-friendly copy and denying leaves the app usable.

## Known limitations

| Limitation | Detail |
|---|---|
| AI needs matching iPhone + Siri language | Apple Intelligence refuses when device and Siri languages differ — the English (Ireland) incident. Fix is in Settings, not in the app. |
| No Apple Intelligence → splitter | Devices without Apple Intelligence (and all simulators) always get the line-splitter fallback; scans still work, just dumber. |
| `.flipstudy` doesn't launch from Files | Tapping a `.flipstudy` file in Files does not yet open FlipStudy; import must start from a share sheet into the app. |

## Release record

| Date | Build | Layers run | Result | Notes |
|---|---|---|---|---|
| 2026-08-04 | 1.3 (5) | 1; 2 (S1 partial, S4) | L1 green — 5 suites, 38 tests, 0 failures. S1: launch, New Deck menu, blank-deck create, deck on shelf, card sheet renders (screenshotted); card *save* blocked by simulator keyboard synthesis (tooling, not app — covered by §3 daily use). S4: deck survived app relaunch. | S2/S3 and the on-device pass still owed before submission. Upload of 1.3 (5) itself still blocked on Xcode 26.6 first-run (admin password). |
| 2026-08-04 | 1.4 (7) | 1 | L1 green — 6 suites (adds VocabPairDetectorTests), 0 failures. Uploaded to App Store Connect ("Upload succeeded"). | Carries the paired-vocab detector and the OCR replace/pre-clean fixes. Build 6 was rejected at upload: it was still labeled 1.3, and 1.3 had been **approved** while we worked — an approved version is closed to new builds. On-device pass (§3) still owed before submitting for review. |
| 2026-08-04 | 1.4 (9) | 1 | L1 green — 7 suites (adds TextLayoutTests), 0 failures. Uploaded and attached to the 1.4 version in App Store Connect. Release build confirmed on simulator with Pro **locked**, proving criterion 22 (the Debug unlock is compiled out). | **The build that ships 1.4.** Builds 7 and 8 were both uploaded before the TextRecognizer fixes landed at 14:13, so neither contained multi-language OCR or wrapped-line rejoining — the two headline items in the release notes. Always check what a build predates before attaching it. Submission still blocked on the IAP review screenshot, which must be uploaded by hand. |
| 2026-08-04 | 1.4 (10) | 1 | L1 green — 8 suites, 0 failures. Installed on the physical iPhone and uploaded to App Store Connect. | **The build that ships.** Folds the card verifier and the edge-quote fix into 1.4 rather than splitting a 1.5 — 1.4 was still a draft, so there was no reason to submit twice. Reported from a scanned Italian list: `<<Io - I` reached a card with the guillemet misread intact. |
|  |  |  |  |  |

### Before archiving for upload — check the release train

Apple closes a version to new builds the moment that version is **approved**,
and Xcode never bumps `MARKETING_VERSION` for you (it's a release decision, not
a build artifact). So before archiving: look up the app's current state in App
Store Connect. If the last version was approved or released, bump
`MARKETING_VERSION` — a build number bump alone will be rejected with
`ERROR ITMS-90062` / "Invalid Pre-Release Train".
