# TruthLens

Native SwiftUI app (iOS, iPadOS, macOS) that scans photos, videos and audio for signs of AI generation,
flags scams / catfishing / political propaganda, fact-checks the claim attached to the media, and drafts
replies sized to each platform's character limit.

## Install

```bash
./setup.sh      # needs Xcode + Homebrew; generates the project and opens it
```
Then choose **My Mac** or your device, set your Team under *Signing & Capabilities*, press **⌘R**.
First launch asks for your Anthropic API key (stored in the Keychain).

## How it works

| Layer | What it does |
|---|---|
| `MetadataAnalyzer` (on-device) | C2PA / Content Credentials, IPTC `trainedAlgorithmicMedia`, generator strings, PNG prompt chunks, camera EXIF |
| `ClaudeClient.analyze` | Sends downscaled image (or 5 video frames) + metadata findings to Claude; returns score, reasons, risk flags |
| Web search tool | Fact-checks claims and any post URL you supply |
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
