#!/usr/bin/env bash
# One-step setup: installs XcodeGen if needed, generates TruthLens.xcodeproj, opens it in Xcode.
set -euo pipefail
cd "$(dirname "$0")"

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required (App Store → Xcode), then run: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate
open TruthLens.xcodeproj
echo "Opened in Xcode. Pick a destination (My Mac, or your iPhone/iPad), set your Team under Signing, press ⌘R."
