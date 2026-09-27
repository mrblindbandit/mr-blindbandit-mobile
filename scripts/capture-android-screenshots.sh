#!/usr/bin/env bash
# Captures Google Play phone screenshots on a running emulator (1080x1920, 9:16).
# Used by .github/workflows/store-screenshots.yml. Signed-in screens use the debug-only
# StoreScreenshotMode (Android/.../StoreScreenshotMode.kt); release builds never include it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="store-screenshots/android"
PKG="net.mrblindbandit.app"
APK="Android/app/build/outputs/apk/debug/app-debug.apk"
mkdir -p "$OUT"

adb wait-for-device
adb install -r "$APK"
adb shell wm size
adb shell cmd uimode night yes || true

# Clean status bar (System UI demo mode).
adb shell settings put global sysui_demo_allowed 1
demo() { adb shell am broadcast -a com.android.systemui.demo -e command "$@" > /dev/null; }
demo enter
demo clock -e hhmm 0941
demo battery -e level 100 -e plugged false
demo network -e wifi show -e level 4
demo network -e mobile show -e datatype none -e level 4
demo notifications -e visible false

shot() { adb exec-out screencap -p > "$OUT/$1.png"; echo "Captured $1"; }

# Public sign-in screen: a normal launch with no account (clear any saved session first).
adb shell pm clear "$PKG" > /dev/null
adb shell am start -W -n "$PKG/.MainActivity"
sleep 20
shot "01-sign-in"

n=2
for screen in home music listen community profile create connect more settings accessibility; do
  adb shell am force-stop "$PKG"
  sleep 1
  adb shell am start -W -n "$PKG/.MainActivity" --ez store_screenshots true --es screen "$screen"
  case "$screen" in music|community|profile|bites) sleep 25 ;; *) sleep 10 ;; esac
  if [ "$screen" = "accessibility" ]; then
    # Scroll Settings down to the Accessibility section.
    adb shell input swipe 540 1600 540 700 800
    sleep 3
  fi
  shot "$(printf '%02d' "$n")-$screen"
  n=$((n + 1))
done

demo exit || true
ls -la "$OUT"
