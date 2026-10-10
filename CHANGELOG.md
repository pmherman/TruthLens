# Changelog

## Unreleased

### Added
- **Listen to replies:** a Listen button (with pause, resume and stop) reads a drafted reply or Community Note aloud. Choose a speed (slow, normal, fast) and a voice. It uses Apple's on-device voices, so it's free, works offline, and nothing is sent anywhere. Links, markdown and emoji are skipped so it reads naturally.
- **History tab:** every AI scan and fact check is saved with a reduced-quality image, the claim, the result and the whole follow-up thread. Tap an item to reopen it in its own tab and keep going (follow-ups, replies, Community Notes).
- **Storage meter:** History shows how much space it uses and offers **Clear history** in one tap. A switch turns saving off.
- **Protect items:** protected items (lock icon) are kept when you clear history or bulk-delete. Delete one item at a time from its menu, or use **Select** to protect or delete several at once. Deleting a protected item always asks first.
- Search and filter history by AI Scans or Fact Checks.
- **Search depth:** Quick (up to 3 searches), Standard (5) or Thorough (8) on the Fact Check tab. Fewer searches is faster.
- **Live progress:** the fact check now streams, showing what it's searching and reading, with a **Cancel** button.
- **Back to results:** editing a claim no longer throws away the last result. Use "Back to previous results" (or the toolbar button) to return to it without searching again.
- **Follow-ups and challenges:** ask questions about a result or challenge it. Challenges are fact-checked with fresh searches, and the rating only changes if verified sources support it. Accept a suggested revision with one tap and it updates the rating, headline and sources used by replies and Community Notes.

### Changed
- Fact-check answers are tighter (shorter explanation, up to 5 sources), which cuts the time spent writing the response.

## 0.0.3 — Alpha (2026-10-10)

### Added
- **Draft a Community Note:** from any fact-check result, draft a neutral Meta Community Note (500 characters including the source link). Pick which source to link, edit the text, and copy it to paste into Meta. A heads-up appears when the claim was rated true or unverified, since notes are for adding missing context.

## 0.0.2 — Alpha (2026-10-10)

### Added
- **Fact Check tab:** check a statement or post on its own, separate from AI scanning. Paste text, add who said it and a link, or attach a screenshot.
- Ratings: True, Mostly true, Partially true, Misleading, Mostly false, False, Unverified, and Not a factual claim, each with a plain-English explanation and key evidence.
- Cited sources show publisher, what each source found, and whether it supports or contradicts the claim. Links the search never returned are removed, and a rating with no verifiable source falls back to Unverified.
- Draft a reply from a fact check, with the same platform limits and tones as the AI scan.

- **About & version:** Settings has an About section with the version, developer credit, GitHub link and a bug-report link. The macOS About window shows the same.
- The app version is now taken from the git tag at build time, so it always matches the release. Builds past a tag say "unreleased changes".

### Changed
- The AI Scan tab is now media-only. The post-text/link context box and the inline fact-check card moved to the Fact Check tab.

## 0.0.1 — Alpha (2026-10-09)

First internal alpha of TruthLens, a native SwiftUI app for macOS, iOS and iPadOS.

### What's in this build
- **Media scanning:** analyze photos, videos and audio for signs of AI generation.
- **On-device metadata analysis:** C2PA / Content Credentials, IPTC `trainedAlgorithmicMedia`, known generator strings, PNG prompt chunks and camera EXIF. A hard embedded AI marker overrides the model's visual opinion.
- **Claude-powered analysis:** sends a downscaled image (or 5 sampled video frames) plus the metadata findings and returns a score, reasons and risk flags.
- **Risk flags:** scam, catfishing, political, propaganda, deepfake, misinformation and commercial.
- **Fact-checking:** web search for the claim attached to the media and any post URL you supply.
- **Reply drafting:** replies sized to each platform's character limit (Threads 500, X 280, Bluesky 300, Facebook 8,000, …), hard-trimmed to fit.
- **App icon:** new lens-and-checkmark icon for all platforms.
- **Security:** your Anthropic API key is stored in the Keychain.

### Known limitations
- No detector is reliable on pixels alone. Results are evidence, not proof.
- Audio: metadata and context only. There is no waveform analysis yet.
- Stripped metadata (most social downloads) proves nothing either way.
- Images are sent to Anthropic's API; videos send 5 sampled frames.
- Requires your own Anthropic API key (asked on first launch).
- macOS build is signed with a personal development certificate and is not notarized (see install notes).

### Install (macOS)
1. Unzip `TruthLens-<version>-alpha-macOS.zip` and move `TruthLens.app` to Applications.
2. First launch: right-click the app, choose **Open**, then confirm. If macOS still blocks it, run `xattr -cr /Applications/TruthLens.app`.
3. Enter your Anthropic API key when prompted.
