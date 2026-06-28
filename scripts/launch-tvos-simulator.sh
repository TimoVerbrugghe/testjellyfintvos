#!/usr/bin/env bash
set -euo pipefail

SCHEME="JellyfinTVOSDemoApp"
BUNDLE_ID="com.timo.jellyfintvosdemo"
APP_NAME="JellyfinTVOSDemoApp"

DEVICE_ID="${1:-}"
if [[ -z "$DEVICE_ID" ]]; then
  DEVICE_ID="$(xcrun simctl list devices available | awk '/-- tvOS/{flag=1;next}/--/{flag=0}flag && /Apple TV 4K \\(3rd generation\\)/{print $NF; exit}' | tr -d '()')"
fi

if [[ -z "$DEVICE_ID" ]]; then
  echo "No available tvOS simulator found."
  exit 1
fi

xcrun simctl boot "$DEVICE_ID" || true
open -a Simulator

xcodebuild \
  -scheme "$SCHEME" \
  -destination "id=$DEVICE_ID" \
  build -quiet

BIN_PATH="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type f -path "*/Build/Products/Debug-appletvsimulator/$APP_NAME" | head -n 1)"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Built executable not found at: $BIN_PATH"
  exit 1
fi

APP_DIR="$(mktemp -d)/$APP_NAME.app"
mkdir -p "$APP_DIR"
cp "$BIN_PATH" "$APP_DIR/$APP_NAME"
chmod +x "$APP_DIR/$APP_NAME"

cat > "$APP_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>MinimumOSVersion</key><string>16.0</string>
  <key>UIDeviceFamily</key><array><integer>3</integer></array>
  <key>LSRequiresIPhoneOS</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key><true/>
  </dict>
</dict>
</plist>
PLIST

xcrun simctl install "$DEVICE_ID" "$APP_DIR"
xcrun simctl launch "$DEVICE_ID" "$BUNDLE_ID"

echo "Launched $APP_NAME on tvOS simulator $DEVICE_ID"
