# Changelog

All notable changes to **Mr. Blindbandit Mobile** are documented in this file.

This project uses a simple public release sequence. iOS and Android are kept on the same public release line whenever both platforms are part of the release. Earlier entries were reconstructed from repository history so the project has a clean, continuous public record from the initial app through the current release.

---

## [1.5] — 2026-09-16

### Added

- Calling-first native iOS navigation with dedicated Phone and Messages tabs.
- Official LiveKit Swift SDK integration for realtime voice, video, and data transport.
- LiveKit Cloud Development Token Server support for backend-free device testing.
- Native CallKit incoming and outgoing call presentation.
- Native dial keypad with VoiceOver labels and haptic feedback.
- Voice-call controls for mute, speaker, answer, decline, and hang up.
- Video-call controls with local and remote video rendering.
- Realtime test messaging with local message history.
- First-launch communication profile with username and unverified phone-number routing.
- Communications settings for LiveKit test connectivity, alerts, call behavior, and tester identity.
- iOS system-default ringtone integration for CallKit calls.

### Changed

- iOS version advanced to **1.5 (build 5)**.
- The iOS app is now organized around **Phone, Messages, Home, Create, and More**.
- Creator tools remain fully available but no longer dominate the primary tab bar.
- Settings and More were reorganized into production-style sections with cleaner labels and less explanatory clutter.
- Camera and microphone permission descriptions now explicitly cover voice and video calling.
- Launch presentation now reflects calls, messages, music, and creator tools.
- LiveKit test mode is visibly enabled and locked on in this development build.

### Security & Testing

- LiveKit API secrets are not embedded in the app.
- Test phone numbers are routing identifiers only and do not require SMS verification.
- Development Token Server mode remains intentionally limited to testing and must be replaced by server-issued tokens before production communications launch.
- Existing APNs registration remains available; production PushKit wake-up for closed-app incoming calls is a follow-up layer.

---

## [1.4] — 2026-09-15

### Added

- Native creator-tool hub on iOS.
- Native audio-conversion workflow on iOS.
- Native art-track generation workflow on iOS.
- Expanded native creator utility collection.
- Native creator toolkit tab on Android.
- Twenty additional native Android creator utilities.
- Versioned, professional CI artifact filenames for both platforms.
- Formal release/versioning checklist in `RELEASING.md`.
- Canonical project changelog.

### Changed

- Canonical public release version aligned to **1.4**.
- iOS version set to **1.4 (build 4)**.
- Android version aligned to **1.4.0 (versionCode 4)**.
- Public app naming standardized to **Mr. Blindbandit**.
- README rewritten around the current cross-platform product, distribution status, accessibility model, security model, and release discipline.
- CI artifact names updated from stale 1.3 labels to 1.4.
- Android CI SDK setup hardened for more reliable builds.

### Fixed

- Swift continuation/compiler issues in native iOS media tools.
- Version-label mismatch where the iOS binary reported 1.4 while GitHub artifact/documentation labels still reported 1.3.
- Android release metadata lagging behind the current release line.

---

## [1.3] — 2026-09-14

### Added

- Native Android application built with Kotlin and Jetpack Compose.
- Android System WebView integration for trusted first-party content.
- TalkBack-focused navigation and semantics.
- Android camera, microphone, notification, and file-picker permission handling.
- Firebase Cloud Messaging scaffolding.
- Expanded native iOS settings and accessibility preferences.
- Branded pulsing logo, waveform loader, and progress presentation.
- VoiceOver page-load announcements.
- Reduced-motion support.
- iOS and Android CI pipelines with tests and downloadable build artifacts.

### Changed

- Project expanded from an iPhone companion into a two-platform mobile codebase.
- First-party web routing and security policy hardened on both platforms.
- Native settings expanded to expose accessibility, privacy, browser, permission, and app-version information.

### Security

- Continued separation of mobile-client configuration from reusable backend secrets.
- Trusted-domain rules limited in-app browsing to approved first-party HTTPS hosts.

---

## [1.2] — 2026-09-14

### Added

- APNs registration framework.
- Native notification permission controls.
- Camera and microphone capture/permission infrastructure.
- Native file-upload support for website workflows.
- Branded launch experience and app icon assets.
- Pull-request build validation.

### Changed

- Native mobile capabilities expanded beyond basic web navigation.
- Device permissions moved behind explicit operating-system controls.
- Build validation became part of the development workflow.

---

## [1.1] — 2026-09-14

### Added

- Native tab-based navigation.
- Device-owner authentication / biometric lock support.
- Authenticated website companion flows.
- Initial native settings and security-oriented app shell improvements.

### Changed

- The project moved from a minimal wrapper toward a structured native companion application.

---

## [1.0] — 2026-09-14

### Added

- Initial Mr. Blindbandit iOS application.
- Swift/Xcode project configuration.
- First-party website companion experience.
- Initial unsigned iOS build packaging.
- Foundation for later native navigation, permissions, accessibility, and creator features.

---

## Release policy

For every future release, update the source versions, build numbers, CI artifact names, README release table, and this changelog in the same release commit or pull request.

See `RELEASING.md` for the release checklist.
