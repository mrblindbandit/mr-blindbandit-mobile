# Release Process

This document defines the release checklist for **Mr. Blindbandit Mobile**.

The goal is simple: the version shown in the apps, source configuration, GitHub Actions, documentation, pull requests, and downloadable artifacts must always agree.

## Canonical release version

Current release: **1.4**

- iOS: `MARKETING_VERSION = 1.4`
- iOS build: `CURRENT_PROJECT_VERSION = 4`
- Android: `versionName = 1.4.0`
- Android build: `versionCode = 4`

## Required release checklist

Before merging a release:

- Update iOS `MARKETING_VERSION` in `project.yml`.
- Increment iOS `CURRENT_PROJECT_VERSION`.
- Update Android `versionName` in `Android/app/build.gradle.kts`.
- Increment Android `versionCode`.
- Update iOS CI artifact names in `.github/workflows/ios.yml`.
- Update Android CI artifact names in `.github/workflows/android.yml`.
- Update the versioned output filename in `build-unsigned.sh` if required.
- Update the current-release table in `README.md`.
- Add a complete entry to `CHANGELOG.md`.
- Make the pull-request title and release notes use the same version.
- Run iOS tests and confirm unsigned IPA packaging succeeds.
- Run Android unit tests and lint.
- Confirm Android debug APK compilation succeeds.
- Verify that the generated artifact filenames contain the expected version.
- Confirm the app Settings/About surface reports the expected version on both platforms.

## Artifact naming standard

Use these formats:

- iOS artifact: `Mr-Blindbandit-iOS-vX.Y-unsigned-IPA`
- iOS file: `Mr-Blindbandit-iOS-vX.Y-unsigned.ipa`
- Android artifact: `Mr-Blindbandit-Android-vX.Y-debug-APK`
- Android file: `Mr-Blindbandit-Android-vX.Y-debug.apk`

Production store builds should use corresponding signed release naming and must not be described as unsigned/debug artifacts.

## Versioning rule

- Patch-level fixes that do not materially change the public app may increment a build number while keeping the same marketing version.
- Public feature releases increment the marketing version.
- iOS and Android should stay on the same public release line whenever both platforms ship together.

## Changelog rule

Every public release gets its own heading in `CHANGELOG.md` with the release date and relevant sections such as:

- Added
- Changed
- Fixed
- Accessibility
- Security
- Removed

Do not silently rewrite historical release notes after publication except to correct factual errors.

## Security rule

Never commit signing keys, Apple private keys, Firebase server credentials, reusable master API secrets, production tokens, or other long-lived private credentials to the repository or mobile binaries.
