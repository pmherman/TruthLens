# TruthLens

Native SwiftUI app (iOS, iPadOS, macOS) with two tools, each in its own tab:

- **AI Scan** – checks photos, videos and audio for signs of AI generation and flags scams / catfishing /
  political propaganda.
- **Fact Check** – checks a statement or post (typed, linked, or from a screenshot) against independent
  sources and rates it True, Mostly true, Partially true, Misleading, Mostly false, False or Unverified, with an
  explanation and cited sources.

Both can draft replies sized to each platform's character limit.

## Install

```bash
./setup.sh      # needs Xcode + Homebrew; generates the project and opens it
```
Then choose **My Mac** or your device, set your Team under *Signing & Capabilities*, press **⌘R**.
An Anthropic API key is optional (Settings → stored in the Keychain). See *With and without a key* below.

## With and without a key
| | No key | With a key |
|---|---|---|
| AI Scan | File metadata / Content Credentials check (no score is invented) | + Claude inspects the pixels |
| Fact Check | Not available (needs web search) | Searches independent sources, rates the claim |
| Replies, Community Notes | Apple Intelligence on-device (macOS 26 / iOS 26+, free, private, simpler writing) | Claude, or the on-device model if you prefer |
| Follow-ups | Answered on-device from the result only | Challenges are fact-checked with fresh searches |
| History, Stats, audio playback | Yes | Yes |

## How it works

| Layer | What it does |
|---|---|
| `MetadataAnalyzer` (on-device) | C2PA / Content Credentials, IPTC `trainedAlgorithmicMedia`, generator strings, PNG prompt chunks, camera EXIF |
| `ClaudeClient.analyze` | Sends downscaled image (or 5 video frames) + metadata findings to Claude; returns score, reasons, risk flags |
| `ClaudeClient.factCheck` | Web-searches primary data and independent outlets, returns a rating, explanation, evidence and per-source findings. Any cited URL the search didn't actually return is dropped |
| `ReplyPlatform` | Per-platform limits (Threads 500, X 280, Bluesky 300, Facebook 8,000, …); output is hard-trimmed to fit |

A hard embedded AI marker overrides the model's visual opinion.

## Limits (be honest with yourself about these)
- No detector is reliable on pixels alone. Results are evidence, not proof; the UI says so.
- Audio: only metadata/context for now. There is no waveform analysis yet.
- Stripped metadata (most social downloads) proves nothing either way.
- Images are sent to Anthropic's API. Videos send 5 sampled frames.

## Next ideas
Share extension ("Scan with TruthLens" from any app), on-device Core ML detector as a first pass,
reverse-image search for catfishing, audio spectral model, history tab with SwiftData.

## Versioning and releases
The app's version comes from the latest git tag (`vX.Y.Z`); there is no version number to edit by hand.
`tools/stamp_version.sh` runs on every build and writes the tag into the app (build number = commit count).
Builds made after the tag, or with uncommitted edits, show "unreleased changes" in Settings and About.

To release: update `CHANGELOG.md`, commit, then
```bash
git tag -a v0.0.2 -m "TruthLens 0.0.2" && git push origin main v0.0.2
xcodebuild -project TruthLens.xcodeproj -scheme TruthLens -configuration Release -derivedDataPath build build
```
