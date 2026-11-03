#!/usr/bin/env bash
# Build, Developer ID–sign, notarize, package DMG, and print SHA-256.
#
# Usage:
#   export NOTARY_PROFILE="nimbus-notary"
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"  # optional
#   ./scripts/release.sh
#   ./scripts/release.sh --skip-notarize

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Nimbus"
CONFIG="Release"
APP_NAME="Nimbus"
DIST="$ROOT/dist"
ARCHIVE="$DIST/$APP_NAME.xcarchive"
EXPORT_DIR="$DIST/export"
APP="$EXPORT_DIR/$APP_NAME.app"
SKIP_NOTARIZE=0

for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
  esac
done

VERSION="$(grep 'MARKETING_VERSION' Nimbus.xcodeproj/project.pbxproj | head -1 | sed 's/.*=[[:space:]]*//;s/;//' | tr -d ' ')"
BUILD="$(grep 'CURRENT_PROJECT_VERSION' Nimbus.xcodeproj/project.pbxproj | head -1 | sed 's/.*=[[:space:]]*//;s/;//' | tr -d ' ')"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

mkdir -p "$DIST"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$DMG"
rm -f "$DIST"/*.SHA256.txt

echo "==> Version $VERSION ($BUILD)"
echo "==> Building archive…"

xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  -destination 'generic/platform=macOS,arch=arm64' \
  clean archive

echo "==> Exporting Developer ID app…"

EXPORT_PLIST="$DIST/ExportOptions.plist"
cat > "$EXPORT_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>destination</key>
  <string>export</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST"

if [[ ! -d "$APP" ]]; then
  echo "error: expected $APP after export" >&2
  exit 1
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "==> Re-signing with $SIGN_IDENTITY…"
  codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --verbose=2 "$APP"
fi

echo "==> Creating DMG…"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$APP" \
  -ov -format UDZO \
  "$DMG"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "error: set NOTARY_PROFILE or pass --skip-notarize" >&2
    echo "Create a profile: xcrun notarytool store-credentials \"nimbus-notary\"" >&2
    exit 1
  fi
  echo "==> Submitting for notarization…"
  xcrun notarytool submit "$DMG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  echo "==> Stapling…"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
else
  echo "==> Skipping notarization (--skip-notarize)"
fi

CHECKSUM="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "$CHECKSUM  $(basename "$DMG")" | tee "$DIST/$APP_NAME-$VERSION.SHA256.txt"

echo ""
echo "Done."
echo "  DMG:      $DMG"
echo "  SHA-256:  $CHECKSUM"
echo ""
echo "GitHub Release:"
echo "  gh release create \"v$VERSION\" \"$DMG\" \"$DIST/$APP_NAME-$VERSION.SHA256.txt\" \\"
echo "    --title \"Nimbus $VERSION\" \\"
echo "    --notes \"Verify: shasum -a 256 $(basename "$DMG") — see PRIVACY.md / TERMS.md / SECURITY.md\""
