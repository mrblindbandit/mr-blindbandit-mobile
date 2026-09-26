# Changelog

All notable changes to **Mr. Blindbandit Mobile** are documented in this file.

This project uses a simple public release sequence. iOS and Android are kept on the same public release line whenever both platforms are part of the release. Earlier entries were reconstructed from repository history so the project has a clean, continuous public record from the initial app through the current release.

---

## [1.7] — 2026-09-26

### Fixed

- Calls and messages work again on both platforms. The apps now use the live `/v1/social/*` endpoints
  with usernames and unwrap the API's `{ success, data }` envelope.
- Account deletion now calls `POST /v1/privacy/delete`, then deletes the Clerk user and erases local data.
- Push tokens are registered with the Blindbandit API (iOS APNs; Android FCM once Firebase is configured).
- iOS video calls now show the remote and local video.
- An active call survives tab changes because one communications service is shared app-wide.

### Added

- Report (person or message) and Block, with confirmation, in every conversation (Guideline 1.2).
- A full Settings screen on both platforms: account, sign-out, delete account, notifications,
  accessibility (haptics, speech feedback and rate, high contrast, reduce motion), audio and calls,
  appearance, privacy and data, legal, support, about, and open-source licenses.
- A shared design system (Dynamic Type / sp text, 44–48 pt targets, high-contrast themes).
- Android release signing from environment variables or CI secrets, a Gradle wrapper, and instrumented tests.
- A CI placeholder-content gate (`scripts/check-placeholders.sh`).

### Removed

- The first-launch mass permission request. Permissions are now asked in context.
- Unused Photos and Bluetooth permission strings (iOS), and the iPad device family.
- Developer-only screens and text (site keys, owner token, SDK status rows).
- The non-functional phone keypad.

---

## [1.6] — 2026-09-18

### Added

- Production communications services on iOS and Android backed by authenticated Blindbandit API requests.
- Server-issued, short-lived LiveKit room grants for voice/video calls.
- Server-backed conversation/message loading and send flows.
- First-launch native permission onboarding.
- iOS `PrivacyInfo.xcprivacy` privacy manifest.
- Source-side Sign in with Apple enablement and entitlement on iOS.
- Production account-deletion services for app/auth data flows.
- Android API 36 target and unsigned release-AAB validation in CI.

### Changed

- Canonical release moved to **iOS 1.6 build 6** and **Android 1.6.0 versionCode 6**.
- Connect surfaces now use the production communications layer rather than local/demo DM state.
- LiveKit access is obtained from authenticated server flows; the shipping source no longer includes a reusable/test participant-token fallback.
- Android toolchain moved to AGP 8.10.1 / Gradle 8.11.1 with SDK 36 validation.
- CI artifacts renamed for v1.6 and expanded to include Android unsigned release-bundle validation.
- README, release process, integration notes, secrets examples, and store-compliance documentation updated to match v1.6.

### Removed

- Legacy iOS and Android LiveKit scaffold services.
- Legacy local/demo direct-message stores.
- Obsolete scaffold-token configuration from client examples and secrets bridges.

### Fixed

- iOS and Android unit tests that still asserted the v1.5 release number.
- Stale v1.5 documentation and release metadata references in current-release guidance.

### Security

- Calls/messages require the active Clerk-authenticated production path.
- Reusable Clerk secrets, LiveKit API credentials, OAuth client secrets, signing credentials, APNs private keys, and Firebase service credentials remain server/build-infrastructure only.
- First-party HTTPS host restrictions remain enforced for in-app web content.

---

## [1.5] — 2026-09-18

### Added

- LiveKit Connect scaffold: real Room.connect using gitignored scaffold token (falls back to POST /v1/livekit/token when available); TEST SCAFFOLD UI labeling.
- Full Connect DMs: 1:1 threads, text + attachments + hold-to-talk voice notes over LiveKit data packets, typing + sent/delivered/read receipts, local thread persistence.
- Connect UI sounds + haptics (ringback, selectable ringtones including ambient pack, notification tones, call/DM event feedback) with Settings toggles and pickers.
- Auth: Google + email primary; Sign in with Apple and Phone OTP feature-flagged off (Clerk Production: Apple/Phone disabled).
- About Us: Privacy Policy (https://mrblindbandit.net/privacy), Terms, Support mailto:business@mrblindbandit.net, version 1.5.
- Brand visuals: gold loader, call background, DM empty-state art; App Icon source from gold/black mark.
- Clerk authentication onboarding with **Continue with Apple**, **Continue with Google**, and **Continue with email** before unlocking the main app (App Store Guideline 4.8).
- In-app **Delete account** path with web confirmation (App Store Guideline 5.1.1).
- LiveKit Connect hub: voice calls, video calls, messaging, and voice notes (record / play / send) on iOS and Android.
- Listen hub with Spotify, Apple Music, Amazon Music, Audiomack, YouTube Music, SoundCloud, Tidal deep links plus first-party music pages and on-device pins.
- More hub: profile, account, website shortcuts, legal links, share, sign out, settings.
- Musician Studio tools: metronome, key/BPM helper, setlist notes, release checklist, lyric scratchpad, loudness tips, cover size checker, hashtag/blurb helper, capo/transpose, practice timer (Android mirrors core set).
- Branded spinning Blindbandit Records gold logo loaders and progress overlays on both platforms.
- Privacy Policy and Terms of Use links in auth, Settings, and More.
- Secrets scaffolding via gitignored `Secrets.local.swift` / `Android/local.properties` with `Config/Secrets.example`.
- Store compliance notes (export encryption, Play Data safety, Sign in with Apple entitlement).

### Changed

- Canonical public release version aligned to **1.5**.
- iOS version set to **1.5 (build 5)**; Android **1.5.0 (versionCode 5)**.
- Main navigation: **Home · Create · Connect · Listen · More** (Settings via More).
- Camera / microphone usage strings updated for voice/video calls and voice notes; Bluetooth usage for call headsets.
- Settings reorganized: Account, Communications, Notifications, Appearance & media, Permissions, Browser, Accessibility, Privacy & security, Legal & compliance, About.
- CI artifact names and release documentation updated for 1.5.

### Accessibility

- VoiceOver labels/hints on auth, Connect, Listen, More, musician tools, and loaders.
- TalkBack content descriptions, headings, live regions, and 48dp touch targets on new Android surfaces.
- Reduced-motion respected by spinning / pulsing brand loaders.

### Security

- Clerk publishable key and LiveKit URL only in client; secret keys and LiveKit API secrets remain server-side.
- Short-lived LiveKit tokens via secure config pattern (scaffold token gitignored).
- First-party HTTPS URL policy unchanged for in-app WebView.

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
- Android adaptive launcher icon and branded loading experience.
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
