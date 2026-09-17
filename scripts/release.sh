#!/usr/bin/env bash
# Builds, signs and packages a DKB Secret release entirely on this Mac
# (docs/release.md). Same shape as DKB Monitor's and DKB Downloader's
# release.sh, minus Sparkle: this app is installed on this machine only,
# so there is no update feed to sign for.
#
# Signing uses the self-signed "DKB Secret Local Signing" certificate named
# in Local.xcconfig (scripts/create-signing-cert.sh). No Apple Developer
# Program, no notarization — the app never leaves this Mac.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="DKBSecretApp"
TEST_SCHEME="DKBSecretAppTests"
PROJECT="DKBSecretNative.xcodeproj"
APP_NAME="DKB Secret"
PROJECT_YML="project.yml"

[ -f Local.xcconfig ] || { echo "Error: Local.xcconfig is missing. Run scripts/create-signing-cert.sh first." >&2; exit 1; }
IDENTITY=$(sed -nE 's/^CODE_SIGN_IDENTITY *= *(.*)$/\1/p' Local.xcconfig)
[ "$IDENTITY" != "-" ] || { echo "Error: Local.xcconfig is ad-hoc. A release must use the local certificate (scripts/create-signing-cert.sh)." >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Run: brew install create-dmg" >&2; exit 1; }

# The .xcodeproj is gitignored, so it must exist before the app tests run.
echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Testing DKBSecretCore"
(cd DKBSecretCore && swift test)

echo "==> Testing DKBSecretApp"
xcodebuild test -project "$PROJECT" -scheme "$TEST_SCHEME" -destination "platform=macOS" -quiet

# project.yml is the source of truth — xcodegen regenerates Info.plist from
# it on every `generate`. Both version fields get the same MAJOR.MINOR.PATCH.
CURRENT_VERSION=$(grep -m1 'CFBundleShortVersionString:' "$PROJECT_YML" | sed -E 's/.*CFBundleShortVersionString: *"?([^"]*)"?/\1/')
SUGGESTED_VERSION=$(awk -F. '{print $1"."$2"."$3+1}' <<< "$CURRENT_VERSION")
read -rp "Current version is $CURRENT_VERSION. New version (e.g. $SUGGESTED_VERSION) [Enter to keep]: " INPUT
VERSION="${INPUT:-$CURRENT_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Error: version must be MAJOR.MINOR.PATCH" >&2; exit 1; }
sed -i '' -E "s/(CFBundleShortVersionString: )\"?[^\"[:space:]]*\"?/\1\"$VERSION\"/" "$PROJECT_YML"
sed -i '' -E "s/(CFBundleVersion: )\"?[^\"[:space:]]*\"?/\1\"$VERSION\"/" "$PROJECT_YML"
echo "==> Releasing version $VERSION"
xcodegen generate

OUT_DIR="release-output/$VERSION"
mkdir -p "$OUT_DIR"
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Building (Release, signed with \"$IDENTITY\")"
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "platform=macOS" -quiet

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Error: no app at $APP_PATH — the build produced nothing." >&2; exit 1; }

echo "==> Verifying the built app"
codesign --verify --deep --strict "$APP_PATH"
# Into a variable first: `grep -q` closing the pipe early makes codesign
# exit non-zero under pipefail, which read as "no runtime flag".
SIGNATURE=$(codesign -dvv "$APP_PATH" 2>&1)
grep -q 'flags=.*runtime' <<< "$SIGNATURE" || { echo "Error: Hardened Runtime is not set on the Release build." >&2; exit 1; }
# The two entitlements the plan allows, and nothing else (Phase 9 audit #5).
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -oE '<key>[^<]+</key>' | sort | tr -d '\n')
EXPECTED='<key>com.apple.security.app-sandbox</key><key>com.apple.security.files.user-selected.read-write</key>'
[ "$ENTITLEMENTS" = "$EXPECTED" ] || { echo "Error: unexpected entitlements: $ENTITLEMENTS" >&2; exit 1; }
echo "    entitlements OK, hardened runtime OK"

echo "==> Creating DMG"
DMG_PATH="$OUT_DIR/DKB-Secret-$VERSION.dmg"
rm -f "$DMG_PATH"
create-dmg \
  --volname "$APP_NAME" \
  --window-pos 200 120 \
  --window-size 660 400 \
  --icon-size 100 \
  --icon "$APP_NAME.app" 160 185 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 460 185 \
  "$DMG_PATH" \
  "$APP_PATH"

cp -R "$APP_PATH" "$OUT_DIR/"
echo
echo "Done: $DMG_PATH"
echo "Install with: ./scripts/install-local.sh $VERSION"
