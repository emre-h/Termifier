#!/bin/bash
set -euo pipefail

VERSION=$(grep 'MARKETING_VERSION' project.yml | grep -v '\$(' | sed 's/.*"\(.*\)"/\1/')
APP_PATH="/tmp/TermifierRelease/Build/Products/Release/Termifier.app"
ZIP_PATH="/tmp/Termifier.zip"

echo "=== Termifier Release v$VERSION ==="

# 1. Check required env vars
echo "Checking required environment variables..."
: "${APPLE_API_KEY:?APPLE_API_KEY is not set}"
: "${APPLE_API_KEY_ID:?APPLE_API_KEY_ID is not set}"
: "${APPLE_API_ISSUER:?APPLE_API_ISSUER is not set}"
echo "All required environment variables are set."

# 2. Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate
echo "Xcode project generated."

# 2.5. Build termifier-session (host binary + Linux remote payloads).
# The "Bundle Session Daemon" / "Bundle Remote Session Binaries"
# postBuildScripts in project.yml hard-fail a Release build when any of
# these are missing, so this must run before xcodebuild.
echo "Building termifier-session (host + Linux remote targets)..."
scripts/build-session.sh --all
echo "termifier-session build complete."

# 3. Build
echo "Building Termifier (Release)..."
xcodebuild \
  -project Termifier.xcodeproj \
  -scheme Termifier \
  -configuration Release \
  ARCHS=arm64 \
  CODE_SIGN_IDENTITY="Developer ID Application: Yuuichi Eguchi (PQQBSRKD72)" \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=PQQBSRKD72 \
  -derivedDataPath /tmp/TermifierRelease \
  clean build
echo "Build succeeded."

SIGN_IDENTITY="Developer ID Application: Yuuichi Eguchi (PQQBSRKD72)"
# 4. Sign the bundled termifier-session host binary. cargo produces it
# only linker-adhoc-signed, and the outer app's non---deep signature
# does not re-sign nested Mach-O files, so notarization needs this
# explicit Developer ID + hardened runtime + timestamp signature.
# The Linux payloads under Resources/session-remote/ are ELF, not
# Mach-O: codesign cannot sign them and seals them as plain resources.
SESSION_HOST_BIN="$APP_PATH/Contents/Resources/bin/termifier-session"
if [ ! -f "$SESSION_HOST_BIN" ]; then
  echo "ERROR: bundled termifier-session not found at $SESSION_HOST_BIN"
  exit 1
fi
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime "$SESSION_HOST_BIN"

# 5. Sign the outer app after signing nested Mach-O binaries.
codesign --force --sign "$SIGN_IDENTITY" --timestamp --options runtime \
  --entitlements Termifier/Termifier.entitlements "$APP_PATH"
echo "Bundled binaries and app signed."

# 3.5d. Pre-notarization verification gate (spctl skipped — requires notarization)
echo "Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "Code signature verification passed."

# 4. Zip for notarization
echo "Creating zip for notarization..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Zip created at $ZIP_PATH."

# 5. Submit for notarization
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
  --key "$APPLE_API_KEY" \
  --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER" \
  --wait
echo "Notarization complete."

# 6. Staple
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"
echo "Stapling complete."

# 6.5. Post-staple verification
echo "Verifying stapled app..."
codesign --verify --deep --strict "$APP_PATH"
xcrun stapler validate "$APP_PATH"
echo "Stapled app verification passed."

# 7. Re-zip with stapled ticket
echo "Creating final zip with stapled ticket..."
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "Final zip created at $ZIP_PATH."

# 7.1. Post-zip verification
echo "Verifying final distributed artifact..."
VERIFY_DIR=$(mktemp -d)
ditto -x -k "$ZIP_PATH" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Termifier.app"
spctl --assess --type exec "$VERIFY_DIR/Termifier.app"
rm -rf "$VERIFY_DIR"
echo "Distributed artifact verification passed."

# 8. Push to remote
echo "Pushing to origin main..."
git push origin main
echo "Push complete."

# 9. Create GitHub release
echo "Creating GitHub release v$VERSION..."
git fetch --tags --force
PREV_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
if [ -n "$PREV_TAG" ]; then
  NOTES=$(git log --pretty=format:"- %s" "$PREV_TAG"..HEAD)
else
  NOTES=$(git log --pretty=format:"- %s")
fi
RELEASE_BODY="## What's Changed
$NOTES"
gh release create "v$VERSION" "$ZIP_PATH" \
  --title "Termifier v$VERSION" \
  --notes "$RELEASE_BODY"
echo "GitHub release v$VERSION created."

echo "=== Release v$VERSION complete ==="
