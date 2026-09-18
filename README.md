<div align="center">

# Mr. Blindbandit Mobile

### Version 1.6 — accessibility-first creator + communications app

**Accessibility-first • Creator-focused • Security-conscious • Cross-platform**

Mr. Blindbandit Mobile is the native iOS and Android companion for the Mr. Blindbandit / Blindbandit Records ecosystem, combining creator tools, music, secure account access, voice/video calling, messaging, and trusted first-party web experiences.

[![Website](https://img.shields.io/badge/Website-mrblindbandit.net-111111?style=for-the-badge&logo=googlechrome&logoColor=white)](https://mrblindbandit.net)
[![Release](https://img.shields.io/badge/Release-v1.6-111111?style=for-the-badge)](CHANGELOG.md)
[![iOS](https://img.shields.io/badge/iOS-17%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#ios)
[![Android](https://img.shields.io/badge/Android-26%2B-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#android)
[![Accessibility](https://img.shields.io/badge/Accessibility-VoiceOver_%2B_TalkBack-111111?style=for-the-badge)](#accessibility)

**Repository:** [`mrblindbandit/mr-blindbandit-mobile`](https://github.com/mrblindbandit/mr-blindbandit-mobile)

</div>

---

## Current release

| Platform | Public version | Build/code | Minimum OS | CI validation artifact |
|---|---:|---:|---:|---|
| iOS | 1.6 | 6 | iOS 17 | `Mr-Blindbandit-iOS-v1.6-unsigned-IPA` |
| Android | 1.6.0 | 6 | Android 8 / API 26 | `Mr-Blindbandit-Android-v1.6-debug-APK` + unsigned AAB |

Version 1.6 productionizes authentication and communications: Clerk-backed sessions, Sign in with Apple on iOS, server-authorized LiveKit room grants, server-backed calls/messages, first-launch permission onboarding, account deletion, an iOS privacy manifest, Android API 36 targeting, and stricter store-validation CI.

The CI artifacts are **validation builds**, not store-signed releases. App Store/TestFlight and Google Play distribution still require the appropriate signing, provisioning, store-console declarations, screenshots/metadata, and final device verification.

See [CHANGELOG.md](CHANGELOG.md) and [RELEASING.md](RELEASING.md).

---

## Product principles

1. **Accessibility is architecture.** VoiceOver and TalkBack support are release requirements.
2. **Creators should be able to work from a phone.** Native media and creator workflows should not assume a desktop.
3. **Mobile clients are inspectable.** Reusable backend credentials stay server-side.
4. **Communications are authenticated.** Calls and messages use the active Clerk session and the Blindbandit production API.
5. **Web content stays bounded.** Only approved HTTPS first-party hosts remain inside the trusted in-app browser surface.

---

## Version 1.6 highlights

### Authentication and account safety

- Clerk-backed Google and email sign-in
- Sign in with Apple enabled on iOS with the required entitlement
- Native session gating
- Device-owner authentication support on iOS
- In-app account deletion wired to the production deletion flow
- Privacy Policy and Terms access from the app
- Client binaries contain only client-safe public identifiers/endpoints

### Calls and messaging

- Native Calls / Messages / Keypad surfaces
- Voice and video calling through LiveKit
- Short-lived LiveKit grants minted by the authenticated server flow
- Server-backed conversations and messages
- Incoming call/message deep-link routing
- Mute, camera, call-state, and accessible call controls
- No reusable LiveKit token or test-token fallback in the v1.6 shipping path

### Creator and music features

- Native creator-tool hub
- Audio conversion workflow
- Art-track generation workflow
- Additional native media utilities
- File import/export flows
- Listen hub with external music-service handoff
- First-party site, portal, account, support, and ecosystem links

### Permissions and privacy

- First-launch native permission onboarding
- Camera and microphone runtime handling
- Photo/file access for user-started actions
- Notification permission handling
- Bluetooth usage descriptions for compatible call audio
- `PrivacyInfo.xcprivacy` included on iOS
- HTTPS-first trusted-host policy

### Accessibility

- VoiceOver-conscious labels, hints, focus, and announcements on iOS
- TalkBack-focused Compose semantics on Android
- Dynamic Type / large-text support
- Reduced-motion preferences
- Accessible loading, error, and call states
- Screen-reader-aware first-party WebView integration
- Physical-device VoiceOver/TalkBack verification remains part of release QA

---

# iOS

The iOS app uses **SwiftUI**, **WKWebView**, ClerkKit, and LiveKit and targets iOS 17+.

Core capabilities include native tab navigation, authentication, calls/messages, creator tools, trusted first-party browsing, native file selection, permissions, APNs registration plumbing, accessibility settings, branded launch/loading states, account deletion, and privacy-manifest declarations.

### iOS CI artifact

- Artifact: `Mr-Blindbandit-iOS-v1.6-unsigned-IPA`
- File: `Mr-Blindbandit-iOS-v1.6-unsigned.ipa`

The IPA is intentionally unsigned and exists to validate compilation. A normal iPhone/App Store build requires Apple signing and provisioning.

---

# Android

The Android app uses **Kotlin**, **Jetpack Compose**, Clerk, LiveKit, Android System WebView, AndroidX, Material 3, and Firebase libraries.

Release metadata:

- `versionName = 1.6.0`
- `versionCode = 6`
- `minSdk = 26`
- `targetSdk = 36`

Core capabilities include native authentication, Calls / Messages / Keypad, creator tools, trusted WebView content, TalkBack semantics, file selection, runtime permissions, notification handling, deep links, accessibility preferences, account deletion, and production communications API integration.

### Android CI artifacts

- Debug APK artifact: `Mr-Blindbandit-Android-v1.6-debug-APK`
- Debug file: `Mr-Blindbandit-Android-v1.6-debug.apk`
- Store-validation bundle artifact: `Mr-Blindbandit-Android-v1.6-unsigned-AAB`

The debug APK and unsigned AAB are CI validation outputs. Google Play release signing remains a deployment responsibility.

---

# Production communications model

The app does not mint privileged LiveKit credentials locally.

1. User authenticates through Clerk.
2. The native app sends the active Clerk bearer token to `https://api.mrblindbandit.net`.
3. The Blindbandit API authorizes call/message operations.
4. For calls, the server returns a short-lived LiveKit room grant.
5. The client connects to LiveKit with that short-lived grant.
6. Messages/conversations are handled through authenticated Blindbandit API endpoints.

Reusable Clerk secrets, LiveKit API keys/secrets, OAuth client secrets, APNs private keys, Firebase service-account credentials, and signing keys must never be committed to the mobile repository or embedded in the app binaries.

---

# Trusted first-party hosts

Current trusted HTTPS hosts include:

- `mrblindbandit.net`
- `www.mrblindbandit.net`
- `portal.mrblindbandit.net`
- `api.mrblindbandit.net`
- `clerk.mrblindbandit.net`
- `accounts.mrblindbandit.net`

Cleartext HTTP and look-alike domains are not trusted first-party destinations.

---

# Building locally

## Android

Requirements: JDK 17, Android SDK/platform 36, and a Gradle environment compatible with the project.

```bash
gradle -p Android testDebugUnitTest --stacktrace
gradle -p Android lintDebug --stacktrace
gradle -p Android assembleDebug --stacktrace
gradle -p Android bundleRelease --stacktrace
```

## iOS

Requirements: macOS, Xcode, and XcodeGen.

```bash
bash build-unsigned.sh
```

The script generates the Xcode project, builds the Release configuration without code signing, and packages the versioned unsigned IPA in `dist/`.

---

# Project structure

```text
.
├── .github/workflows/
│   ├── ios.yml
│   └── android.yml
├── App/
├── AppTests/
├── Android/
├── Config/
├── scripts/
├── build-unsigned.sh
├── project.yml
├── CHANGELOG.md
├── RELEASING.md
└── README.md
```

---

# Release discipline

The canonical public release is **1.6**.

Every release must update together:

- iOS `MARKETING_VERSION`
- iOS `CURRENT_PROJECT_VERSION`
- Android `versionName`
- Android `versionCode`
- CI validation and artifact names
- README current-release metadata
- `CHANGELOG.md`
- store metadata/release notes

The detailed source and store checklist lives in [RELEASING.md](RELEASING.md). Store policy notes live in [Config/STORE_COMPLIANCE.md](Config/STORE_COMPLIANCE.md).

---

# Distribution status

This repository builds and validates the v1.6 source, but source-control readiness is not the same as a completed store submission.

Before public distribution, use production signing/provisioning, verify account deletion and communications against the deployed production API, complete Apple privacy and Google Play Data safety declarations from actual behavior, provide required review information, run physical-device accessibility/call tests, and upload final screenshots/metadata.

---

# About Mr. Blindbandit

Mr. Blindbandit is an artist, creator, and platform project spanning music, creator tools, accessibility-focused technology, community features, and Blindbandit Records.

**Website:** https://mrblindbandit.net  
**GitHub:** https://github.com/mrblindbandit
