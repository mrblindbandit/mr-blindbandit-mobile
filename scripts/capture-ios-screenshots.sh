#!/usr/bin/env bash
# Captures App Store screenshots in the iOS Simulator (6.9-inch iPhone, 1320x2868).
# Used by .github/workflows/store-screenshots.yml on a macOS runner. Signed-in screens use the
# Debug-only StoreScreenshotMode (App/StoreScreenshotMode.swift); Release builds never include it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="store-screenshots/ios"
BUNDLE_ID="net.mrblindbandit.privateapp"
mkdir -p "$OUT"

UDID=""
for name in "iPhone 17 Pro Max" "iPhone 16 Pro Max" "iPhone Air" "iPhone 16 Plus"; do
  UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
devices = json.load(sys.stdin)["devices"]
for runtime, items in sorted(devices.items(), reverse=True):
    if "iOS" not in runtime:
        continue
    for d in items:
        if d.get("isAvailable") and d.get("name") == name:
            print(d["udid"]); sys.exit(0)
' "$name" || true)
  if [ -n "$UDID" ]; then echo "Using simulator: $name ($UDID)"; break; fi
done
test -n "$UDID" || { echo "No 6.9-inch or 6.7-inch iPhone simulator available"; xcrun simctl list devices available; exit 1; }

xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild build -project Blindbandit.xcodeproj -scheme Blindbandit -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build/Shots \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO > build/xcodebuild-shots.log 2>&1 || { tail -80 build/xcodebuild-shots.log; exit 1; }
APP="build/Shots/Build/Products/Debug-iphonesimulator/Blindbandit.app"
xcrun simctl install "$UDID" "$APP"

xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

shot() { xcrun simctl io "$UDID" screenshot --type=png "$OUT/$1.png"; echo "Captured $1"; }

# Public sign-in screen: a normal launch with no account.
xcrun simctl launch "$UDID" "$BUNDLE_ID"
sleep 20
shot "01-sign-in"

n=2
for screen in home music listen community profile create connect more settings accessibility; do
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" || true
  sleep 1
  xcrun simctl launch "$UDID" "$BUNDLE_ID" -StoreScreenshots YES -StoreScreenshotScreen "$screen"
  case "$screen" in music|community|profile|bites) sleep 25 ;; *) sleep 10 ;; esac
  shot "$(printf '%02d' "$n")-$screen"
  n=$((n + 1))
done

xcrun simctl status_bar "$UDID" clear || true
ls -la "$OUT"
