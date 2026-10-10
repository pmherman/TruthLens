# Changelog

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
1. Unzip `TruthLens-0.0.1-alpha-macOS.zip` and move `TruthLens.app` to Applications.
2. First launch: right-click the app, choose **Open**, then confirm. If macOS still blocks it, run `xattr -cr /Applications/TruthLens.app`.
3. Enter your Anthropic API key when prompted.
