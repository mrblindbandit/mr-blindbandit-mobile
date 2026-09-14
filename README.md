<div align="center">

# Mr. Blindbandit App

### Version 1.3 — iPhone + Android companion apps for the Mr. Blindbandit platform

**VoiceOver-first • TalkBack-first • Security-conscious • Creator-focused**

[![Website](https://img.shields.io/badge/Website-mrblindbandit.net-111111?style=for-the-badge&logo=googlechrome&logoColor=white)](https://mrblindbandit.net)
[![iOS](https://img.shields.io/badge/iOS-17%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](#ios-app)
[![Android](https://img.shields.io/badge/Android-Modern_Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)](#android-app)
[![Accessibility](https://img.shields.io/badge/Accessibility-VoiceOver_%2B_TalkBack-111111?style=for-the-badge)](#accessibility)

**Repository:** `mrblindbandit/mr.-Blindbandit-app`

</div>

---

## Current release

**Version:** 1.3

Version 1.3 expands the project from an iPhone-only companion into a two-platform mobile project with native iOS and Android shells, accessibility-focused web integration, native permissions, file uploads, notification frameworks, deep links, expanded settings, branded loading states, and automated build pipelines.

### Build status

The Android v1.3 CI pipeline now successfully completes:

- Kotlin/Gradle compilation
- Unit tests
- Android lint
- Debug APK compilation
- GitHub Actions artifact upload

The iOS pipeline performs:

- Xcode project generation
- App-icon generation
- iOS unit tests
- Unsigned IPA compilation
- GitHub Actions artifact upload

GitHub Actions workflows live under `.github/workflows/`.

---

## Downloads and build artifacts

GitHub Actions produces downloadable artifacts for testing.

### Android

The Android workflow produces:

`Blindbandit-Android-1.3-debug-APK`

Inside the artifact is:

`app-debug.apk`

This is a compiled **debug APK** intended for development and device testing. It is not a Google Play production release and is not signed with a Play production signing key.

Android workflow:

`https://github.com/mrblindbandit/mr.-Blindbandit-app/actions/workflows/android.yml`

### iPhone

The iOS workflow produces:

`Blindbandit-iOS-1.3-unsigned-IPA`

This is an **unsigned IPA**. It must be signed or installed through an appropriate Apple development/distribution process before it can run on a normal iPhone.

iOS workflow:

`https://github.com/mrblindbandit/mr.-Blindbandit-app/actions/workflows/ios.yml`

> GitHub Actions artifacts are temporary build artifacts. For permanent public distribution, publish signed releases through the appropriate Apple and Google distribution channels or attach release binaries to GitHub Releases.

---

# Overview

The Mr. Blindbandit mobile project is the native mobile layer for the broader **Mr. Blindbandit** and **Blindbandit Records** ecosystem.

The apps provide fast access to:

- `mrblindbandit.net`
- Account and profile features
- Community features
- Media tools
- Label portal features
- Payments and private owner workflows
- Future API-backed native features

The website remains the source of truth for web content while the apps add native navigation, device permissions, accessibility behavior, notifications infrastructure, file selection, security controls, and native operating-system integration.

---

# iOS app

The iPhone app is built with **SwiftUI** and **WKWebView**.

## Current iOS capabilities

- Native SwiftUI shell
- iOS 17+ target
- Native tabs and settings
- WKWebView first-party web experience
- VoiceOver-conscious labels and semantics
- Dynamic Type-friendly native controls
- Device-owner authentication support
- Background privacy handling
- Native back/forward/reload controls
- External link routing
- First-party deep-link handling
- Camera permission framework
- Microphone permission framework
- Native file uploads through WKWebView file inputs
- APNs registration framework
- Local notification permission state
- Push deep-link event handling
- App version shown in Settings
- Branded launch/loading presentation
- Reduced-motion preference
- Page-load announcements preference
- Automated unit-test and unsigned-IPA pipeline

## iOS push notifications

APNs support is scaffolded, but production remote push still requires:

1. A signed/provisioned app with the correct Apple entitlements.
2. Apple Developer push capability configuration.
3. A backend endpoint that securely registers device tokens.
4. A server-side APNs sender.

A reusable private server secret must not be bundled into the distributable app.

---

# Android app

The Android app is a native Kotlin application using **Jetpack Compose**, **Android System WebView**, **AndroidX**, **Material 3**, and Firebase Messaging scaffolding.

## Current Android capabilities

- Native Kotlin/Compose shell
- Home, Website, Media, and Settings areas
- Android System WebView for first-party pages
- TalkBack-focused accessibility behavior
- Native file picker for HTML file-upload controls
- Runtime camera permission handling
- Runtime microphone permission handling
- Android notification permission handling
- First-party media capture permission gating
- Secure mixed-content policy
- Restricted direct file access
- DOM storage support
- Text zoom preference
- Third-party cookie preference
- Media autoplay preference
- Page-load announcements
- Reduced-motion preference
- Keep-screen-awake preference
- Native Back, Reload, and Browser controls
- Safe Browsing support
- External HTTPS, email, and telephone links routed to Android
- First-party deep-link policy
- Branded adaptive launcher icon
- Pulsing branded loading mark
- Animated waveform loader
- Loading progress percentage
- FCM framework integration scaffold
- App version shown in Settings
- Android accessibility-settings shortcut
- App-permissions shortcut
- Website cookie/storage reset option
- Automated unit tests, lint, and APK compilation

## Android WebView and TalkBack

Android System WebView is used deliberately because it integrates with Android's accessibility tree and TalkBack while still allowing the app to add native navigation and permission handling around the website.

The WebView is configured to be accessibility-important and focusable, and the surrounding Compose controls use native Android semantics.

Actual end-to-end accessibility should still be manually verified on physical Android devices with TalkBack enabled. Automated tests can verify code and build behavior, but they cannot completely certify the real screen-reader experience.

## Firebase Cloud Messaging

Firebase Cloud Messaging support is scaffolded in the Android project.

Remote Android push delivery is not active until a Firebase project is connected and the app receives the appropriate Firebase configuration, including `google-services.json` where applicable.

The app is designed so production server credentials stay on the server rather than inside the APK.

---

# Accessibility

Accessibility is a core design requirement for both platforms.

## iPhone targets

- VoiceOver
- Dynamic Type
- Native control semantics
- Clear focus order
- Descriptive button labels
- Reduced Motion
- Readable error states
- Accessible loading states
- Keyboard and switch-control compatibility where supported by native controls

## Android targets

- TalkBack
- Large text
- Display scaling
- High-contrast configurations
- Switch Access
- Keyboard navigation
- Native Compose semantics
- Accessible WebView focus
- Reduced-animation preferences
- Spoken page-load feedback

Because much of the product experience loads first-party web content, website accessibility remains part of the mobile accessibility surface. Native accessibility and web accessibility must be tested together.

---

# First-party web policy

The mobile apps keep trusted Mr. Blindbandit destinations inside the app and route unrelated external destinations to the operating system.

Current trusted HTTPS hosts include:

- `mrblindbandit.net`
- `www.mrblindbandit.net`
- `portal.mrblindbandit.net`
- `api.mrblindbandit.net`
- `clerk.mrblindbandit.net`
- `accounts.mrblindbandit.net`

Cleartext HTTP and look-alike/spoofed hostnames are not treated as trusted first-party pages.

---

# Native permissions

The apps provide frameworks for permissions that modern web-powered mobile features need.

## Camera

First-party website camera requests can be mapped to native operating-system permission prompts.

## Microphone

First-party website microphone requests can be mapped to native operating-system permission prompts.

## File uploads

- iOS uses WKWebView's native file-upload behavior.
- Android maps web file inputs into the native Android document/photo picker.

## Notifications

- iOS uses the APNs registration framework.
- Android uses notification permission handling and Firebase Cloud Messaging scaffolding.

Production remote delivery still requires the corresponding backend and platform credentials.

---

# Settings

Version 1.3 expands native settings on both platforms.

Settings can include or expose:

- App version/build information
- Accessibility preferences
- Page-load announcements
- Reduced-motion behavior
- Browser text sizing
- Cookie/session controls
- Camera/microphone permission access
- Notification status
- Website-storage clearing
- Native system accessibility settings
- Native app-permission settings
- Browser behavior preferences

---

# Security model

The apps intentionally do not embed reusable master backend secrets.

The security model separates:

1. **Device security** — Face ID, Touch ID, passcode, Android device protections.
2. **Website authentication** — user sign-in/session state.
3. **Server authorization** — account roles and protected APIs.
4. **Domain policy** — only approved first-party hosts stay inside the trusted web surface.
5. **Platform permissions** — camera, microphone, notifications, and file access remain permission-controlled.

Mobile binaries must be treated as inspectable. Private API secrets and production push credentials belong on trusted backend infrastructure.

---

# Project structure

```text
.
├── .github/
│   └── workflows/
│       ├── ios.yml
│       └── android.yml
├── App/
│   ├── BlindbanditApp.swift
│   ├── MobileCapabilities.swift
│   ├── Blindbandit.entitlements
│   └── Assets.xcassets/
├── AppTests/
│   └── BlindbanditTests.swift
├── Android/
│   ├── app/
│   │   └── src/
│   │       ├── main/
│   │       │   ├── java/net/mrblindbandit/app/
│   │       │   └── res/
│   │       └── test/
│   └── build.gradle.kts
├── scripts/
│   └── GenerateAppIcon.swift
├── build-unsigned.sh
├── project.yml
└── README.md
```

---

# Building Android locally

Requirements:

- JDK 17
- Android SDK
- Android platform/build tools matching the project configuration
- Gradle 8.9 or a compatible project-supported Gradle environment

From the repository root:

```bash
gradle -p Android testDebugUnitTest
gradle -p Android lintDebug
gradle -p Android assembleDebug
```

The debug APK is generated at:

```text
Android/app/build/outputs/apk/debug/app-debug.apk
```

---

# Building iOS locally

Requirements:

- macOS
- Xcode
- XcodeGen

Generate/build using the repository scripts and project configuration.

The GitHub workflow creates an unsigned IPA for automated testing and artifact distribution.

An unsigned IPA is not equivalent to an App Store/TestFlight production build.

---

# Testing strategy

Version 1.3 uses CI to catch build and policy regressions.

## Android automated checks

- Kotlin/Java compilation
- Unit tests
- First-party URL policy tests
- Preference tests
- Android lint
- Debug APK build

## iOS automated checks

- Xcode project generation
- Unit tests
- First-party URL policy tests
- App-version configuration checks
- Accessibility-preference defaults
- Unsigned IPA build

## Manual testing still required

Before calling a release fully accessibility-tested, verify on real devices:

- VoiceOver navigation on iPhone
- TalkBack navigation on Android
- Large text / display scaling
- Reduced motion
- Camera and microphone prompts
- File selection/upload
- Login/session flows
- External links
- Deep links
- Offline and failed-network states
- Notification permissions
- Push behavior once backend delivery is configured

---

# Distribution notes

## Android debug APK

The CI-generated APK can be installed for testing on Android devices that allow installation from the selected source.

For a production Play Store build, create a properly signed release/AAB pipeline and configure Google Play signing.

## iOS unsigned IPA

The CI-generated IPA is unsigned and intended as a build artifact. It needs appropriate Apple signing/provisioning before normal device installation.

For broader distribution, use TestFlight, App Store distribution, or another permitted signing/testing workflow.

---

# Versioning

Current development release:

**1.3**

Both apps expose version information in their native Settings/About surfaces so testers can confirm which build they are using.

---

# Roadmap

Planned and future-friendly areas include:

- Production APNs device registration and push delivery
- Production Firebase/FCM configuration
- Signed Android release/AAB pipeline
- Signed iOS/TestFlight pipeline
- More native media-suite integrations
- Native share-sheet workflows
- Better offline/error recovery
- Universal/app links
- Secure owner/admin authentication flows using short-lived backend tokens
- More automated security/accessibility tests
- Physical-device VoiceOver/TalkBack regression testing
- Additional native shortcuts and widgets
- Future Android/iOS API-backed features

---

# About Mr. Blindbandit

Mr. Blindbandit is an artist, creator, and platform project spanning music, media tools, accessibility-focused technology, community features, and Blindbandit Records.

Website: **https://mrblindbandit.net**

---

## Development warning

This repository is under active development. Debug APKs and unsigned IPAs are testing artifacts, not production-store releases. Do not place production private keys, reusable server secrets, signing keys, or other sensitive credentials in source control or mobile client code.
