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
- `FlipStudyTests/DeckTransferTests.swift` — a deck encodes to `.flipstudy` and decodes back with nothing lost or reordered (the share/import round-trip).
- `FlipStudyTests/AnswerLanguageTests.swift` — the answer/translation language for vocab card backs is chosen correctly from the deck and device settings.
- `FlipStudyTests/FamilyCodeTests.swift` — a FlipStudy Cloud code is parsed the same whether typed or scanned, junk is rejected, and the engine stays on-device without one.

The Worker has its own check, which must pass before handing out any code —
it catches the case where the app and the minting script disagree about hashing,
which looks exactly like a typo'd code:

```bash
cd worker && node scripts/verify-hash.mjs
```

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
| a | New Deck (with Pro unlocked) → Scan a Page | camera/scan UI opens (photo-library fallback acceptable in sim); without Pro the item reads "Scan a Page (Pro)" and opens the paywall |
| b | Provide a **paired-vocabulary** page image ("water — acqua" style lines) | preview lists the page's own pairs verbatim before anything is saved |
| c | Confirm | deck exists with the previewed cards |
| d | Provide a Q&A page image instead | with host Apple Intelligence: real AI question/answer cards; without: the orange banner names why the model can't run and Make Cards shows the reason as an error — **no cards are invented either way** |

Screenshot checkpoint: the card preview sheets (b, d).
Sim caveat: whether the AI runs in the simulator depends on the **host Mac** —
with Apple Intelligence enabled on macOS, the sim proxies the host model and
the AI paths work (verified 2026-08-31 on this Mac); without it, only the
paired-vocabulary page yields cards and the AI paths show the unavailability
reason. Real-hardware behavior is still §3.

### S3 — Import a shared `.flipstudy` file
| Step | Action | Must show |
|---|---|---|
| a | Open a known-good `.flipstudy` file into the app | import preview shows deck name and card count |
| b | Confirm import | deck appears on the shelf; spot-check two cards |

Screenshot checkpoint: the import preview.

### S4 — Persistence across force-quit
After S1 and S3: force-quit the app, relaunch → decks, cards, and study
progress are all still present. Screenshot checkpoint: the shelf after relaunch.

### S5 — FlipStudy Cloud family code
| Step | Action | Must show |
|---|---|---|
| a | Settings with no code | "FlipStudy Cloud" section offers **Enter Family Code** and nothing else |
| b | Tap it | the grown-up gate appears *before* the code screen |
| c | Enter a wrong code | a plain-language rejection; cloud stays off |
| d | Enter a real code | section shows "FlipStudy Cloud is on" and the code's label |
| e | Scan a Page / Type a Subject | cards are generated, and the footers say FlipStudy Cloud made them |
| f | Turn on "Make cards on this phone instead" | footers return to the on-device wording; in the simulator the unavailability banner reappears |
| g | Remove Code | section returns to (a); the smart features gate as they did in 1.5 |

Screenshot checkpoint: (a), (d), and a generated preview from (e).
Sim caveat: QR scanning needs real hardware (`DataScannerViewController`), so
the **Scan QR Code** button is hidden in the simulator — type the code there and
test the QR path on the phone.

### What the simulator cannot cover (do not file as bugs)
- **AI card generation on a Mac without Apple Intelligence** — the model is
  only available in the simulator when the host Mac runs Apple Intelligence
  (the sim proxies the host model). Without it, Type a Subject and the Q&A /
  plain-list scan paths show the unavailability reason instead of cards, and
  only the paired-vocabulary scan (deterministic) produces cards in the sim.
- **StoreKit purchases** — need the `FlipStudy.storekit` configuration attached
  via an Xcode Run, or a sandbox account on a real device; a bare sim launch
  shows no products.

## 3. On-device pass (before every release)

On the physical iPhone:

1. **Scan a real Q&A page with AI** — cards are real question/answer pairs
   from the model (answers paraphrased/cleaned, not raw OCR lines).
2. **Scan a vocab list** — backs come out translated into the deck's answer
   language.
3. **Purchases** — sandbox purchase completes; Restore Purchase restores it.
4. **Share round-trip** — share a deck to Files, then re-import that
   `.flipstudy` file and verify the cards.
5. **Fresh install** — delete the app, reinstall, confirm permission prompts
   (camera/photos) show the kid-friendly copy and denying leaves the app usable.
6. **Scan a family code's QR** — the printed/texted QR redeems without typing.
7. **Cloud on an ineligible iPhone** — on hardware without Apple Intelligence, a
   redeemed code makes the smart features work; removing it hides them again.
8. **Cloud failure modes** — airplane mode mid-request, and a code whose daily
   quota is spent, both show a plain-language reason and produce no cards.

## Known limitations

| Limitation | Detail |
|---|---|
| AI needs matching iPhone + Siri language | Apple Intelligence refuses when device and Siri languages differ — the English (Ireland) incident. The fix is in Settings, not in the app; since 1.5 the app at least *says so* ("Check that your iPhone and Siri languages match") instead of silently degrading. |
| No Apple Intelligence → no smart features | Since 1.5, hardware that can't run Apple Intelligence doesn't see Type a Subject or Scan a Page at all; there is no dumbed-down scan mode. Manual decks, studying, and sharing work everywhere. |
| FlipStudy Cloud needs the internet | The cloud engine is the one flow that cannot work offline. Airplane-mode testing (criterion 21) applies to the on-device path, which is still the default for everyone without a code. |
| `.flipstudy` doesn't launch from Files | Tapping a `.flipstudy` file in Files does not yet open FlipStudy; import must start from a share sheet into the app. |

## Release record

| Date | Build | Layers run | Result | Notes |
|---|---|---|---|---|
| 2026-08-04 | 1.3 (5) | 1; 2 (S1 partial, S4) | L1 green — 5 suites, 38 tests, 0 failures. S1: launch, New Deck menu, blank-deck create, deck on shelf, card sheet renders (screenshotted); card *save* blocked by simulator keyboard synthesis (tooling, not app — covered by §3 daily use). S4: deck survived app relaunch. | S2/S3 and the on-device pass still owed before submission. Upload of 1.3 (5) itself still blocked on Xcode 26.6 first-run (admin password). |
| 2026-08-04 | 1.4 (7) | 1 | L1 green — 6 suites (adds VocabPairDetectorTests), 0 failures. Uploaded to App Store Connect ("Upload succeeded"). | Carries the paired-vocab detector and the OCR replace/pre-clean fixes. Build 6 was rejected at upload: it was still labeled 1.3, and 1.3 had been **approved** while we worked — an approved version is closed to new builds. On-device pass (§3) still owed before submitting for review. |
| 2026-08-04 | 1.4 (9) | 1 | L1 green — 7 suites (adds TextLayoutTests), 0 failures. Uploaded and attached to the 1.4 version in App Store Connect. Release build confirmed on simulator with Pro **locked**, proving criterion 22 (the Debug unlock is compiled out). | **The build that ships 1.4.** Builds 7 and 8 were both uploaded before the TextRecognizer fixes landed at 14:13, so neither contained multi-language OCR or wrapped-line rejoining — the two headline items in the release notes. Always check what a build predates before attaching it. Submission still blocked on the IAP review screenshot, which must be uploaded by hand. |
| 2026-08-04 | 1.4 (10) | 1 | L1 green — 8 suites, 0 failures. Installed on the physical iPhone and uploaded to App Store Connect. | **The build that ships.** Folds the card verifier and the edge-quote fix into 1.4 rather than splitting a 1.5 — 1.4 was still a draft, so there was no reason to submit twice. Reported from a scanned Italian list: `<<Io - I` reached a card with the guillemet misread intact. |
| 2026-08-31 | 1.5 (dev) | 1; 2 (S2) | L1 green — 7 suites, 60 tests, 0 failures (CardGeneratorTests deleted with the splitter). S2 in sim, Debug/Pro: both smart features in the New Deck menu; Q&A page → 3 real AI cards (the host Mac's model proxied into the sim — the sim caveat is host-dependent, not absolute); paired-vocab page → its 6 pairs verbatim, Italian auto-detected; no deck created. | First pass of the AI-only scan gating: fallback generators deleted, AI failures surface as plain-language errors. |
| 2026-08-31 | 1.5 (dev) | 3 (partial, via iPhone Mirroring) | On the physical iPhone 17 (Debug build 11, installed via devicectl, driven over iPhone Mirroring with CGEvent taps): New Deck menu shows both smart features on eligible hardware; Type a Subject "Ordering dinner in Italy" → 11 cards, English fronts, on-device-translated Italian backs, deck created and persisted; Scan a Deck sheet opens with no unavailability banner and the 1.5 copy. | Still owed by hand: camera scan of a real page (Mirroring blocks the camera), the Apple-Intelligence-off banner/error check, and the purchase flow (scheme is staged Release + StoreKit config — one ⌘R covers it). |
|  |  |  |  |  |

### Before archiving for upload — check the release train

Apple closes a version to new builds the moment that version is **approved**,
and Xcode never bumps `MARKETING_VERSION` for you (it's a release decision, not
a build artifact). So before archiving: look up the app's current state in App
Store Connect. If the last version was approved or released, bump
`MARKETING_VERSION` — a build number bump alone will be rejected with
`ERROR ITMS-90062` / "Invalid Pre-Release Train".
