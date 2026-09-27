#!/usr/bin/env bash
# Builds an unsigned Release .app for generic iOS devices and zips it as Payload/<App>.app (.ipa).
# The IPA must be re-signed (for example with a free Apple ID via Sideloadly/AltStore) to install.
set -euo pipefail
VERSION=$(sed -n "s/.*MARKETING_VERSION: '\(.*\)'/\1/p" project.yml | head -1)
xcodegen generate
xcodebuild -project Blindbandit.xcodeproj -scheme Blindbandit -configuration Release \
  -destination 'generic/platform=iOS' -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' -type d | head -1)
test -n "$APP" || { echo "No .app produced" >&2; exit 1; }
test -f "$APP/Info.plist" || { echo "$APP has no Info.plist" >&2; exit 1; }
rm -rf dist/Payload
mkdir -p dist/Payload
cp -R "$APP" dist/Payload/
rm -f "dist/Mr-Blindbandit-iOS-v${VERSION}-unsigned.ipa"
(
  cd dist
  zip -qry "Mr-Blindbandit-iOS-v${VERSION}-unsigned.ipa" Payload
)
rm -rf dist/Payload
echo "Wrote dist/Mr-Blindbandit-iOS-v${VERSION}-unsigned.ipa"
