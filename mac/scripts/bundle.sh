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
  codesign --force --sign - "$APP"
  echo "Signed ad-hoc: the system will forget Screen Recording permission after every rebuild."
fi
echo "Built $APP"
