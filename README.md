<div align="center">

# Mr. Blindbandit Mobile

### iOS 1.5 — calling-first communications + creator platform

**Accessibility-first • Communications-first on iOS • Creator-focused • Security-conscious**

Mr. Blindbandit Mobile combines native calling, messaging, creator tools, secure integrations, and connected Mr. Blindbandit ecosystem features.

[![Website](https://img.shields.io/badge/Website-mrblindbandit.net-111111?style=for-the-badge&logo=googlechrome&logoColor=white)](https://mrblindbandit.net)
[![iOS](https://img.shields.io/badge/iOS-v1.5-000000?style=for-the-badge&logo=apple&logoColor=white)](#ios)
[![Android](https://img.shields.io/badge/Android-v1.4-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#android)
[![Accessibility](https://img.shields.io/badge/Accessibility-VoiceOver_%2B_TalkBack-111111?style=for-the-badge)](#accessibility)

**Repository:** [`mrblindbandit/mr-blindbandit-mobile`](https://github.com/mrblindbandit/mr-blindbandit-mobile)

</div>

---

## Current development releases

| Platform | Version | Build | Minimum OS | CI artifact |
|---|---:|---:|---:|---|
| iOS | 1.5 | 5 | iOS 17 | `Mr-Blindbandit-iOS-v1.5-unsigned-IPA` |
| Android | 1.4.0 | 4 | Android 8.0 / API 26 | `Mr-Blindbandit-Android-v1.4-debug-APK` |

**iOS 1.5** is the first calling-first release. It adds native LiveKit voice/video transport, CallKit integration, realtime messaging, a dial keypad, communications settings, haptics, and a reorganized app shell while preserving the existing creator suite.

Android remains on the 1.4 creator-platform release line until the communications architecture is intentionally ported to Android.

See **[CHANGELOG.md](CHANGELOG.md)** for the complete version history.

---

## What this project is

Mr. Blindbandit Mobile is the native mobile layer for the broader **Mr. Blindbandit** and **Blindbandit Records** ecosystem.

The apps combine native mobile controls with trusted first-party web experiences from `mrblindbandit.net`. Native code handles the parts that benefit most from operating-system integration: calling, messaging, accessibility, permissions, files, notifications, security, media utilities, and polished navigation.

The project is designed around four ideas:

1. **Accessibility is core architecture.** VoiceOver and TalkBack support are product requirements.
2. **Calling should feel native.** iOS communications use native SwiftUI, CallKit, AVFoundation, and LiveKit rather than a web call surface.
3. **Creators should be able to work from a phone.** Media utilities and creator workflows remain first-class features.
4. **Mobile clients should never become a secret vault.** Reusable backend credentials stay server-side.

---

## iOS 1.5 highlights

### Calls & messages

- Calling-first tab layout: Phone, Messages, Home, Create, More
- Native dial keypad with haptics and VoiceOver labels
- LiveKit voice and video transport
- Native CallKit incoming/outgoing call experience
- Mute, speaker, camera, answer, decline, cancel, and hang-up controls
- Local and remote video rendering
- Realtime LiveKit data-channel messaging
- Local message history
- Configurable message sound/haptic behavior
- iOS system-default incoming ringtone
- Username + unverified phone-number test routing
- LiveKit Development Token Server support for device testing

### Creator tools

- Native creator-tool hub
- Native audio conversion workflow
- Native art-track generation workflow
- Expanded creator utility set
- Improved file import/export flows
- Website-backed media suite remains available under More

### Accessibility

- VoiceOver-first iOS navigation and labels
- TalkBack-first Android navigation and semantics
- Dynamic Type / large-text support
- Reduced-motion preferences
- Page-load announcements
- Accessible call controls and keypad
- Native accessibility-settings shortcuts
- Screen-reader-aware WebView integration

### Platform integration

- Camera and microphone permission handling
- Native file pickers/uploads
- APNs registration framework on iOS
- Firebase Cloud Messaging scaffold on Android
- Deep-link routing
- External-link handoff to the operating system
- Device-owner authentication
- Native settings and connection status

---

## Communications testing model

The iOS 1.5 communications layer intentionally uses LiveKit's **Development Token Server** for the first device-testing phase.

- Test mode is visibly enabled and locked on in this build.
- Both devices must use the same LiveKit Cloud Development Token Server ID.
- Phone numbers are unverified routing identifiers inside the app; no SMS verification occurs.
- The LiveKit API secret is not embedded in the app.
- The receiving app must currently be running and connected for direct test calls/messages.
- Production closed-app incoming calling will require PushKit plus server-side call signaling.
- Production authentication will replace development token issuance with short-lived server-issued tokens.
- End-to-end encryption is planned as a later layer rather than being falsely claimed in the test build.

---

## Downloads and CI artifacts

GitHub Actions produces temporary development artifacts for testing.

### iOS

Artifact:

`Mr-Blindbandit-iOS-v1.5-unsigned-IPA`

File inside the artifact:

`Mr-Blindbandit-iOS-v1.5-unsigned.ipa`

The iOS artifact is **unsigned**. It is a build-validation artifact and must be properly signed/provisioned before installation on a normal iPhone.

Workflow: `.github/workflows/ios.yml`

### Android

Artifact:

`Mr-Blindbandit-Android-v1.4-debug-APK`

File inside the artifact:

`Mr-Blindbandit-Android-v1.4-debug.apk`

The Android artifact is a **debug APK** for development and device testing. It is not a production Google Play release and is not signed with a production Play signing key.

Workflow: `.github/workflows/android.yml`

> GitHub Actions artifacts are temporary. Production distribution should use signed builds delivered through the appropriate Apple or Google release channels.

---

# iOS

The iOS app is built with **SwiftUI**, **CallKit**, **LiveKit**, **AVFoundation**, and **WKWebView**, and targets iOS 17 or later.

## Current capabilities

- Native SwiftUI application shell
- Calling-first five-tab navigation
- Native voice and video calls
- Native CallKit call presentation
- Realtime messaging
- LiveKit Development Token Server test connectivity
- Native keypad and communications haptics
- Native Settings and advanced settings
- WKWebView for trusted first-party web content
- VoiceOver-conscious semantics and controls
- Dynamic Type-friendly interfaces
- Device-owner authentication support
- Background privacy handling
- First-party deep-link handling
- Camera and microphone permission framework
- Native file-upload support
- APNs registration framework
- Notification permission state
- Branded launch and loading presentation
- Reduced-motion preference
- Page-load announcements
- Native creator toolkit
- Native audio-conversion tools
- Native art-track generation tools
- Additional creator utilities
- Automated tests and unsigned-IPA compilation

### iOS push notifications

APNs registration is present. Production remote push delivery still requires Apple signing/entitlements and server-side token registration/delivery. Production PushKit signaling for waking the app for incoming calls is not yet connected in the test communications phase.

---

# Android

The Android app remains on the 1.4 release and is built with **Kotlin**, **Jetpack Compose**, **Android System WebView**, **AndroidX**, and **Material 3**.

## Current capabilities

- Native Kotlin/Compose application shell
- Home, Website, Create/Media, and Settings surfaces
- Android System WebView for trusted first-party content
- TalkBack-focused navigation and semantics
- Native file/document picker
- Camera and microphone runtime permissions
- Android notification permission handling
- Safe Browsing and HTTPS-first policy
- Restricted direct file access
- DOM storage support
- Browser text-zoom preference
- Page-load announcements
- Reduced-motion preference
- Keep-screen-awake preference
- Native Back, Reload, and Browser controls
- External HTTPS/email/telephone routing
- First-party deep-link policy
- Adaptive launcher icon and branded loading state
- Firebase Cloud Messaging scaffold
- Native creator toolkit and utility collection
- Automated unit tests, lint, and APK compilation

### Firebase Cloud Messaging

Remote Android push delivery is not active until a production Firebase project/configuration is connected. Production credentials belong on trusted backend infrastructure, not in the APK.

---

# Accessibility

Accessibility is a product requirement, not a post-build add-on.

## iOS targets

- VoiceOver
- Dynamic Type
- Native control semantics
- Logical focus order
- Descriptive call, message, and keypad labels
- Reduced Motion
- Accessible loading/error states
- Keyboard and switch-control compatibility where supported by native controls

## Android targets

- TalkBack
- Large text and display scaling
- High-contrast configurations
- Switch Access
- Keyboard navigation
- Native Compose semantics
- Accessible WebView focus
- Reduced animation
- Spoken page-load feedback

Because the apps intentionally load first-party web content, real accessibility quality depends on **both native app accessibility and website accessibility**. Physical-device VoiceOver and TalkBack testing remains part of release validation.

---

# Security model

The app does not ship reusable master backend secrets.

The security model separates:

1. **Device security** — Face ID, Touch ID, passcode, and Android device protections.
2. **Communications test identity** — username and unverified phone routing for the current LiveKit development phase.
3. **Website authentication** — user sign-in and session state.
4. **Server authorization** — protected APIs and account roles.
5. **Domain policy** — only approved first-party hosts remain inside the trusted in-app web surface.
6. **Platform permissions** — camera, microphone, notifications, photos/files, and related capabilities remain operating-system controlled.

Mobile binaries should always be treated as inspectable. Long-lived private server credentials must remain server-side.

---

# Trusted first-party hosts

Current trusted HTTPS hosts include:

- `mrblindbandit.net`
- `www.mrblindbandit.net`
- `portal.mrblindbandit.net`
- `api.mrblindbandit.net`
- `clerk.mrblindbandit.net`
- `accounts.mrblindbandit.net`

Cleartext HTTP and look-alike/spoofed domains are not treated as trusted first-party destinations.

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
├── scripts/
├── build-unsigned.sh
├── project.yml
├── CHANGELOG.md
├── RELEASING.md
└── README.md
```

---

# Building locally

## Android

Requirements:

- JDK 17
- Android SDK
- Android platform/build tools matching the project configuration
- Gradle 8.9 or compatible project-supported Gradle environment

```bash
gradle -p Android testDebugUnitTest
gradle -p Android lintDebug
gradle -p Android assembleDebug
```

## iOS

Requirements:

- macOS
- Xcode
- XcodeGen

```bash
bash build-unsigned.sh
```

The script generates the Xcode project, resolves the LiveKit Swift package, builds the release configuration without code signing, packages the `.app`, and creates the versioned unsigned IPA in `dist/`.

---

# Release discipline

Current platform releases are **iOS 1.5 (build 5)** and **Android 1.4.0 (versionCode 4)**.

Every release must update the relevant version surfaces together:

- iOS `MARKETING_VERSION`
- iOS `CURRENT_PROJECT_VERSION`
- Android `versionName` when Android is part of the release
- Android `versionCode` when Android is part of the release
- GitHub Actions artifact names
- README current-release table
- `CHANGELOG.md`
- Pull-request/release title and release notes

The detailed release checklist lives in **[RELEASING.md](RELEASING.md)**.

---

# Distribution status

This repository is under active development.

- CI-generated iOS IPAs are unsigned development artifacts.
- CI-generated Android APKs are debug development artifacts.
- Production App Store/TestFlight and Google Play builds require the appropriate signing, provisioning, store configuration, and release pipelines.

Do not commit private signing keys, reusable backend secrets, APNs keys, Firebase server credentials, LiveKit API secrets, or other production secrets to this repository.

---

# About Mr. Blindbandit

Mr. Blindbandit is an artist, creator, and platform project spanning music, creator tools, accessibility-focused technology, community features, and Blindbandit Records.

**Website:** https://mrblindbandit.net

**GitHub:** https://github.com/mrblindbandit
