#!/bin/sh
# Stamps the built app's Info.plist with the version from the latest git tag (vX.Y.Z).
#   CFBundleShortVersionString = tag without the "v"
#   CFBundleVersion            = number of commits (monotonic build number)
#   TruthLensGitDescribe       = `git describe`, e.g. "v0.0.1" or "v0.0.1-3-g6c8410f-dirty"
# With no git history or no tag, the project.yml fallback version is left alone.
set -e
cd "$SRCROOT"
PLIST="$TARGET_BUILD_DIR/$INFOPLIST_PATH"
TAG=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)
[ -n "$TAG" ] || { echo "note: no git tag found, leaving fallback version"; exit 0; }
DESC=$(git describe --tags --match 'v[0-9]*' --dirty 2>/dev/null)
BUILD=$(git rev-list --count HEAD)
PB=/usr/libexec/PlistBuddy
set_key() { "$PB" -c "Set :$1 $2" "$PLIST" 2>/dev/null || "$PB" -c "Add :$1 string $2" "$PLIST"; }
set_key CFBundleShortVersionString "${TAG#v}"
set_key CFBundleVersion "$BUILD"
set_key TruthLensGitDescribe "$DESC"
echo "note: stamped version ${TAG#v} ($BUILD), $DESC"
