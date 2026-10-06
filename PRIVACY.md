# FlipStudy Privacy Policy

_Last updated: October 5, 2026_

FlipStudy is a flashcard study app. This policy explains what the app does and
does not do with information. In short: FlipStudy is built to keep your data on
your device. We do not have accounts and we do not collect analytics.

One optional feature, **FlipStudy Cloud**, does send text to a service we run.
It is off unless someone enters a family code we gave them, and it is described
in full below.

## Information we collect

**We do not collect any personal information.** FlipStudy has no user accounts,
no login, and no analytics or tracking SDKs. The decks and cards you create are
stored only on your device using Apple's on-device storage (SwiftData). We never
receive them.

The one exception is the text you choose to turn into cards while FlipStudy
Cloud is switched on — see below. We do not keep that text, and it is never
linked to a name, an account, or an advertising identifier, because the app has
none of those.

## On-device AI and translation (the default)

By default, FlipStudy generates cards and translations entirely **on your
device** using Apple's built-in on-device models (Foundation Models and the
Apple Translation framework). When you use these default features, **no text
leaves your device and nothing is sent to us or any third party.**

## Optional Cloud AI translation

FlipStudy includes an **optional** feature, turned off by default, that lets you
use a third-party online translation service (Google Cloud Translation or
Microsoft Translator) with **your own API key** that you enter in Settings.

If — and only if — you turn this on and provide your own key:

- The topic text and study terms you ask to translate are sent over an encrypted
  (HTTPS) connection **directly** from your device to the provider you chose
  (Google or Microsoft). The data is not routed through us; we operate no servers.
- Your API key is stored securely in the device Keychain and is used only to
  authenticate those requests. It is never sent to us.
- The provider's own privacy policy governs how they handle that text:
  - Google: https://cloud.google.com/terms/cloud-privacy-notice
  - Microsoft: https://privacy.microsoft.com/privacystatement

You can stop using this feature at any time by turning off Cloud AI in Settings
and removing your API key. When it is off, FlipStudy uses only on-device
processing.

## Optional FlipStudy Cloud (family codes)

FlipStudy Cloud is an **optional** feature, off by default, that makes cards
using a larger AI model than an iPhone can run on its own. It is only available
to someone we have given a **family code** to, entered by hand or scanned from a
QR code. A grown-up has to pass the parental check before a code can be entered.

If — and only if — a code has been redeemed on a device, and FlipStudy Cloud is
the selected engine:

- The text you ask it to turn into cards (the topic you type, or the text
  recognized from a page you scanned) is sent over an encrypted (HTTPS)
  connection to a service we operate on Cloudflare, and from there to
  Cloudflare's Workers AI to generate the cards.
- **That text is not stored.** It is held only for as long as the request takes.
  We keep a per-code counter of how many requests were made, so a code cannot be
  abused; that counter contains no text and nothing about who you are.
- We do not receive your decks, your cards, your study progress, your photos, or
  your name. Reading text from a photo still happens entirely on your device;
  only the recognized text is sent, never the image.
- The code you redeem is exchanged for a token stored in your device Keychain.
  We can switch off a single device or a whole code at any time.
- Cloudflare processes the request as our service provider:
  https://www.cloudflare.com/privacypolicy/

You can stop using this at any time: turn on "Make cards on this phone instead",
or tap **Remove Code**, both in Settings. With it off, card generation is fully
on-device again and nothing is sent anywhere.

## Camera and photo access

FlipStudy may ask for camera or photo library access so you can create cards from
a page you photograph. Any text recognition happens **on your device**. Photos
you choose are not uploaded or stored by us.

## Children's privacy

FlipStudy is intended for students and general audiences. We do not knowingly
collect personal information from anyone, including children. Because the default
experience is fully on-device with no accounts and no data collection, no
personal information about a child is transmitted or stored by us.

The two features that can send text off the device — Cloud Translation and
FlipStudy Cloud — are both off by default and both require a grown-up to pass a
parental check before they can be switched on. Neither sends a name, an email, a
login, or any device identifier that could identify a child, because the app
never collects those in the first place.

## Data sharing and sale

We do not sell, rent, or share your data, and we never will. The only data that
reaches us at all is the text sent while FlipStudy Cloud is switched on, which is
used to generate your cards and is not stored, sold, or used to train anything.

## Changes to this policy

If this policy changes, we will update the date at the top of this page.

## Contact

Questions about this policy can be sent to:
**dwheat@methodical-ep.com**
