#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
command -v xcodebuild >/dev/null
command -v xcodegen >/dev/null
command -v swift >/dev/null

swift scripts/GenerateAppIcon.swift
xcodegen generate
xcodebuild -project Blindbandit.xcodeproj -scheme Blindbandit -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build

app='build/Build/Products/Release-iphoneos/Blindbandit.app'
test -x "$app/Blindbandit"
test -f "$app/AppIcon60x60@2x.png" -o -f "$app/Assets.car"
mkdir -p build/package/Payload
ditto "$app" build/package/Payload/Blindbandit.app
cd build/package
/usr/bin/zip -qry ../Blindbandit-unsigned.ipa Payload
