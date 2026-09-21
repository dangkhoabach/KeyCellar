#!/usr/bin/env bash
# Builds, signs and packages a DKB Secret release entirely on this Mac
# (docs/release.md). Same shape as DKB Monitor's and DKB Downloader's
# release.sh, minus Sparkle: the app has no network entitlement, so there
# is no update feed to sign for.
#
# Signing uses the self-signed "DKB Secret Local Signing" certificate named
# in Local.xcconfig (scripts/create-signing-cert.sh) — it keeps the vault's
# Keychain item out of the `unsigned:` partition (plan D1). No Apple
# Developer Program, no notarization: first launch on another Mac needs
# System Settings › Privacy & Security › Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME="DKBSecretApp"
TEST_SCHEME="DKBSecretAppTests"
PROJECT="DKBSecretNative.xcodeproj"
APP_NAME="DKB Secret"
INFO_PLIST="DKBSecretApp/Info.plist"

[ -f Local.xcconfig ] || { echo "Error: Local.xcconfig is missing. Run scripts/create-signing-cert.sh first." >&2; exit 1; }
IDENTITY=$(sed -nE 's/^CODE_SIGN_IDENTITY *= *(.*)$/\1/p' Local.xcconfig)
[ "$IDENTITY" != "-" ] || { echo "Error: Local.xcconfig is ad-hoc. A release must use the local certificate (scripts/create-signing-cert.sh)." >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "Error: create-dmg not found. Run: brew install create-dmg" >&2; exit 1; }

echo "==> Testing DKBSecretCore"
(cd DKBSecretCore && swift test)

echo "==> Testing DKBSecretApp"
xcodebuild test -project "$PROJECT" -scheme "$TEST_SCHEME" -destination "platform=macOS" -quiet

# Info.plist is the source of truth for the version. Both fields get the
# same MAJOR.MINOR.PATCH.
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")
SUGGESTED_VERSION=$(awk -F. '{print $1"."$2"."$3+1}' <<< "$CURRENT_VERSION")
read -rp "Current version is $CURRENT_VERSION. New version (e.g. $SUGGESTED_VERSION) [Enter to keep]: " INPUT
VERSION="${INPUT:-$CURRENT_VERSION}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Error: version must be MAJOR.MINOR.PATCH (digits only), got \"$VERSION\"." >&2; exit 1; }

# A lower number than the current one would overwrite an older
# release-output/<version> with a newer build and mislabel what is installed.
if [ "$VERSION" != "$CURRENT_VERSION" ] &&
   [ "$(printf '%s\n%s\n' "$CURRENT_VERSION" "$VERSION" | sort -V | tail -1)" != "$VERSION" ]; then
  echo "Error: $VERSION is lower than the current $CURRENT_VERSION." >&2
  exit 1
fi

# Info.plist is edited in place before the build, so any failure from here
# on would otherwise leave it bumped to a version that never shipped.
INFO_PLIST_BACKUP=$(mktemp)
cp "$INFO_PLIST" "$INFO_PLIST_BACKUP"

# One handler, installed once: `$?` inside a trap is whatever ran last, so
# chaining two traps would have the second read the first's exit code.
on_exit() {
  local status=$?
  if [ -n "${BUILD_DIR:-}" ]; then
    rm -rf "$BUILD_DIR"
  fi
  if [ "$status" -ne 0 ]; then
    echo "==> Failed (exit $status) — restoring $INFO_PLIST" >&2
    cp "$INFO_PLIST_BACKUP" "$INFO_PLIST"
  fi
  rm -f "$INFO_PLIST_BACKUP"
}
trap on_exit EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$INFO_PLIST"
echo "==> Releasing version $VERSION"

OUT_DIR="release-output/$VERSION"
mkdir -p "$OUT_DIR"
BUILD_DIR=$(mktemp -d)

echo "==> Building (Release, signed with \"$IDENTITY\", universal arm64+x86_64)"
# Same as DKB Monitor: without the generic destination xcodebuild builds for
# this Mac's own architecture only and Intel Macs would be left out.
xcodebuild build \
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  -destination "generic/platform=macOS" -quiet

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || { echo "Error: no app at $APP_PATH — the build produced nothing." >&2; exit 1; }

echo "==> Verifying the built app"
codesign --verify --deep --strict "$APP_PATH" || {
  echo "Error: $APP_PATH failed signature verification." >&2
  exit 1
}
# Into a variable first: `grep -q` closing the pipe early makes codesign
# exit non-zero under pipefail, which read as "no runtime flag".
SIGNATURE=$(codesign -dvv "$APP_PATH" 2>&1)
grep -q 'flags=.*runtime' <<< "$SIGNATURE" || { echo "Error: Hardened Runtime is not set on the Release build." >&2; exit 1; }
ARCHS_BUILT=$(lipo -archs "$APP_PATH/Contents/MacOS/$APP_NAME")
for arch in arm64 x86_64; do
  grep -qw "$arch" <<< "$ARCHS_BUILT" || {
    echo "Error: binary is missing $arch (built: $ARCHS_BUILT). Intel or Apple Silicon Macs would be left out." >&2
    exit 1
  }
done
# The two entitlements the plan allows, and nothing else (Phase 9 audit #5).
ENTITLEMENTS=$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -oE '<key>[^<]+</key>' | sort | tr -d '\n')
EXPECTED='<key>com.apple.security.app-sandbox</key><key>com.apple.security.files.user-selected.read-write</key>'
[ "$ENTITLEMENTS" = "$EXPECTED" ] || { echo "Error: unexpected entitlements: $ENTITLEMENTS" >&2; exit 1; }
echo "    entitlements OK, hardened runtime OK, architectures: $ARCHS_BUILT"

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
