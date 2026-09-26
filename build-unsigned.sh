#!/usr/bin/env bash
set -euo pipefail
VERSION=$(sed -n "s/.*MARKETING_VERSION: '\(.*\)'/\1/p" project.yml | head -1)
xcodegen generate
xcodebuild -project Blindbandit.xcodeproj -scheme Blindbandit -configuration Release \
  -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -derivedDataPath build/DerivedData build
APP=$(find build/DerivedData -name 'Blindbandit.app' -type d | head -1)
mkdir -p dist/Payload
rm -rf dist/Payload/*
cp -R "$APP" dist/Payload/
(
  cd dist
  zip -qr "Mr-Blindbandit-iOS-v${VERSION}-unsigned.ipa" Payload
)
echo "Wrote dist/Mr-Blindbandit-iOS-v${VERSION}-unsigned.ipa"