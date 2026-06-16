#!/usr/bin/env bash
#
# Build, sign (Developer ID, team SK4GFF6AHN), notarize, staple, and package
# Runse as a standalone .app + .dmg for distribution OUTSIDE the Mac App Store.
#
# Requires: the "Developer ID Application: Chao Lv (SK4GFF6AHN)" signing
# identity in the keychain, and the notarization API key at $NOTARY_KEY.
#
# Usage:  scripts/build-developer-id.sh
# Output: build/developer-id/Runse-<version>.dmg  (notarized + stapled)
set -euo pipefail

TEAM="SK4GFF6AHN"
IDENTITY="Developer ID Application: Chao Lv (${TEAM})"
NOTARY_KEY="${NOTARY_KEY:-$HOME/.appstoreconnect/AuthKey_5MC8U9Z7P9.p8}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-5MC8U9Z7P9}"
NOTARY_ISSUER="${NOTARY_ISSUER:-1200242f-e066-47cc-9ac8-b3affd0eee32}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/developer-id"
DD="$OUT/dd"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> Building Release (Developer ID + Hardened Runtime)…"
xcodebuild -project "$ROOT/RunseMac.xcodeproj" -scheme RunseMac -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  clean build

APP="$DD/Build/Products/Release/RunseMac.app"
[ -d "$APP" ] || { echo "ERROR: app not found at $APP" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILDNUM="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
echo "==> Built Runse ${VERSION} (${BUILDNUM})"

echo "==> Verifying signature + Hardened Runtime…"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --verbose=2 "$APP" 2>&1 | grep -E 'Authority=|TeamIdentifier=|flags=' || true

echo "==> Notarizing the app…"
ZIP="$OUT/Runse-notarize.zip"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait

echo "==> Stapling the app…"
xcrun stapler staple "$APP"

echo "==> Building DMG…"
STAGE="$OUT/dmg"
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Runse-${VERSION}.dmg"
hdiutil create -volname "Runse" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "==> Signing, notarizing, and stapling the DMG…"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
xcrun stapler staple "$DMG"

echo "==> Final verification…"
spctl --assess --type exec -vv "$APP" || true
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"

echo ""
echo "DONE → $DMG"
