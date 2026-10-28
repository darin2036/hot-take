#!/bin/sh
# Builds "Hot Take.app" (a menu-bar app) from the Swift package. Needs only the command line tools.
# Signing: the system ties Screen Recording / Microphone grants to the app's code identity. An ad-hoc
# signature is just the hash of this exact build, so every rebuild loses the grant. Use a real
# certificate (a free "Apple Development" certificate works) and the grant survives rebuilds.
#   RELAYTAKE_SIGN_IDENTITY="Apple Development: you@example.com (TEAMID)" ./scripts/bundle.sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Hot Take.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$(swift build -c release --show-bin-path)/Relaytake" "$APP/Contents/MacOS/Hot Take"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Hot Take</string>
  <key>CFBundleIdentifier</key><string>org.relaytake.mac</string>
  <key>CFBundleName</key><string>Hot Take</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Hot Take</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>org.relaytake.hottake</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>org.relaytake.hottake</string>
    <key>UTTypeDescription</key><string>Hot Take</string>
    <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>hottake</string></array>
    </dict>
  </dict></array>
  <key>NSCameraUsageDescription</key><string>Hot Take shows your camera as a bubble on your screen recording when you choose a camera.</string>
  <key>NSCameraUseContinuityCameraDeviceType</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>Hot Take records your voice into the video when Microphone is on.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Hot Take transcribes recordings on this Mac to make captions.</string>
</dict></plist>
PLIST
IDENTITY="${RELAYTAKE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
if [ -n "$IDENTITY" ]; then
  codesign --force --sign "$IDENTITY" --identifier org.relaytake.mac "$APP"
  echo "Signed with: $IDENTITY"
else
  # No certificate: build ad hoc so the app still runs. An ad-hoc signature is different on every rebuild, so the
  # system forgets the Screen Recording grant each time; a free "Apple Development" certificate avoids that.
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc: the system will forget Screen Recording permission after every rebuild."
  echo "A free Apple Development certificate (or RELAYTAKE_SIGN_IDENTITY) keeps it across rebuilds."
fi

# The system keys Screen Recording, Microphone and Camera grants to the app's "designated requirement". Remember
# it; if it ever changes (a different certificate, or a build that was signed ad hoc), the old grants no longer
# match this app, so clear them and the next launch asks again instead of silently failing. Set
# RELAYTAKE_RESET_PERMISSIONS=1 to clear them on purpose, for a grant that went stale before this check existed.
REQUIREMENT="$(codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => //p')"
STAMP="build/.signing-requirement"
if [ "${RELAYTAKE_RESET_PERMISSIONS:-0}" = "1" ] || { [ -f "$STAMP" ] && [ "$(cat "$STAMP")" != "$REQUIREMENT" ]; }; then
  for service in ScreenCapture Microphone Camera; do tccutil reset "$service" org.relaytake.mac >/dev/null 2>&1 || true; done
  echo "Cleared Hot Take's Screen Recording, Microphone and Camera permissions. Open the app and allow them again;"
  echo "after allowing Screen Recording, quit and reopen the app."
fi
printf '%s' "$REQUIREMENT" > "$STAMP"
echo "Built $APP"
