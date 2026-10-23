# Changelog

All notable changes to **Mr. Blindbandit Mobile** are documented in this file.

This project uses a simple public release sequence. iOS and Android are kept on the same public release line whenever both platforms are part of the release. Earlier entries were reconstructed from repository history so the project has a clean, continuous public record from the initial app through the current release.

---


## 2.0.5 (20)
- Fix: answering a call failed and the caller's side ended right away. The server's "answered on another device" call_end VoIP push also reached the answering iPhone, which tore down the call it was joining (and then reported the failure back to the caller). The app now ignores call_end for a call it is joining.
- Fix: VoIP call invites only ring when addressed to the signed-in account (callee id/handle checked when present; your own outgoing call never rings you; stale pushes after sign-out are rejected).

## 2.0.4 (19)
- Fix: AI chat refused "play X on Apple Music". Music commands are now parsed deterministically and drive MusicKit directly; the instructions tell the model to always use the appleMusic tool; authorization denied/restricted gives spoken guidance; real MusicKit errors are logged (os_log + Settings > AI > Music debug log).

## 2.0.3 (iOS build 18) - 2026-10-23
- Apple Music in the AI chat: MusicKit tool (play, pause, next, previous, queue, search, library shuffle, now playing) through ApplicationMusicPlayer; accessible Now Playing bar; 30-second previews without a subscription; NSAppleMusicUsageDescription.
- AI web search tool through GET /v1/ai/search (Clerk auth), cited links open in SFSafariViewController, "Needs server update" on 404, "Allow AI web search" toggle (default on).
- Owner-only AI Style (Hood/Professional) plus Unfiltered, gated by the server-reported handle; public @AI always Professional; everyone else Professional.
- Responsiveness: AI prewarm at launch and on composer focus, optimistic send with "Sending…", cached inbox plus last 50 messages of the top 8 chats, send/receive haptics, LiveKit host preconnect when the call button shows.
- Opt-in Cloud AI (Workers AI via /v1/ai/chat, image, transcribe, translate, link-check, quota) with per-feature toggles, replies/images left today, on-device fallback on 429/404.
- Fixed fastlane/WhatToTest.txt (2.0.2 and 2.0.3 notes).

## 2.0.2 (iOS build 17) - 2026-10-23
- AI chat backup and restore via `v1/backups/ai-chat`; backups accept `{ciphertext, metadata, updated_at}` and `{v, blob}`.
- Chat settings: flat server fields (`no_store`, `allow_ai`, `screenshot_alerts`, `allow_view_once`, `admins_only_post`, `require_approval`, `my`) decoded and patched; Allow AI switch enforced; Mute notification sound.
- Message pin/unpin syncs to the server; 404/405 handled gracefully (kept on device, announced).
- Recovery passphrase backup (`v1/keys/backup`) sends and reads both shapes; covered by tests.

## 2.0.1 (16)
- Voice messages: press and hold the mic to record (haptic and "Recording"), lift to send ("Sent"), slide left or use the "Cancel recording" action to cancel. Encrypted upload via the attachment path, with a transcript fallback. Listen-once option and 1x, 1.5x and 2x playback.
- Chat header: the contact or group name opens chat info and settings (VoiceOver: "<Name>, chat settings"). The ⋯ More button is gone; call buttons stay.
- Composer tools (mic, poll, camera describe, AI, emoji, silent send, schedule, settings) are available as VoiceOver actions on the message field.
- Blue Verified checkmark on the profile, chat header, chat list, directory, group members and sender names, decoded from the API's `verified` field.
- The AI chat is a warm, casual friend with encrypted, synced memory. It streams replies to VoiceOver, can speak them, and works hands-free by voice. Foundation Models tools cover chats, drafts, reminders, calendar, contacts, places, translation, photo reading, date math, units, memory and notes, plus @Generable memory digests, content tagging, prewarm, context-window summarizing and fallbacks.
- Polls, folders with a Face ID hidden folder, notes to self, Face ID chat lock in DMs and groups, silent send that really sets the silent flag, live call captions, smart search, daily digest, describe my camera, a SensitiveContentAnalysis blur, AI in groups (@AI, /ai, catch-me-up), duress PIN and an encrypted message history backup with restore.

## 2.0.0 (15)
- End-to-end encryption (p256-v1, CryptoKit) for DMs and groups when the server supports it. Keys sync through iCloud Keychain. Includes safety numbers with QR codes, key-change alerts, padding and signed unsend. Older plaintext chats keep working.
- Security & Privacy in every chat: clear from server, disappearing timers (30s to 90d), relay-only, one-tap Unsend, screenshot and recording alerts, Face ID chat lock, hidden previews, link-preview blocking, metadata strip, view-once, receipt and typing switches, export or delete my data, and a security log. Any feature the server doesn't support yet shows "Needs server update".
- App security: relock timeout, app-switcher blur, jailbreak warning, devices and sessions, and an optional recovery passphrase.
- Edit, star, pin, scheduled and silent send, and invite links with approval, slow mode and admins-only posting.
- On-device AI (Apple Intelligence, iOS 26): a permanent AI chat pinned at the top of Messages, @AI in chats (public or private), catch-me-up, smart replies, rewrite, scam warnings, translation with Original (including Cebuano and Tagalog), dictation, natural voices and action detection. Nothing is sent to a server.

## 1.9.0 (14)
- Calls are logged in Phone > Recents: incoming and outgoing calls, whether answered, missed or declined, with the real name, @handle and audio/video type.
- CallKit end reports wait until iOS has registered the call. The server's call_end push ends the call as remote-ended or unanswered.
- Tapping a Recents entry calls back, including at cold launch.
- Notification taps open the right conversation, group or call. Routing reads every payload shape (deep_link/url/link, conversation_id/conversationId/c/thread_id, aps thread-id, group_id, call_id, nested data/payload, or sender handle only), survives cold launch and the Face ID lock, and logs key names only.
- Every message has its own VoiceOver status line under it, in DMs and groups ('Sent/Delivered/Read <time>', 'Read by …'), which updates live. Incoming messages get a time line. The group typing indicator is polled and announced. UI test added.

## [1.9.0 iOS (13)] — 2026-10-23

### Added
- CallKit calling: native incoming call screen (also on the lock screen), Recents with real names (never IDs), answer, decline, hold, mute and video from the system UI, Blind Bandit ringtone, PushKit VoIP pushes, and call back from Recents and Siri.
- Voice and Video buttons in each conversation's top bar.
- Video calls with your own and the other person's video, flip camera, in-app screen share, and switching between voice and video mid-call.
- Group calls with a grid, active speaker highlight, joined/left announcements, add people mid-call, raise hand, in-call chat, mute and quality indicators, an audio output picker, pin video, mute someone just for you, and admin remove.
- Groups tab (replaces Chronicle, which moved to More > Read and listen): create and name a group, group chat with typing, members, admins, rename, add or remove members, leave, delete, group voice and video calls, missed group calls.
- People directory with Message, Call and Video.
- Full-screen incoming call screen. Magic Tap answers or ends the call (setting), and mute is in Actions.
- Status under your messages ("Sent", "Delivered", "Read 5:08 AM", "Read Yesterday 9:14 PM"), included in VoiceOver labels and announced when it changes. Typing bubble, which respects Reduce Motion.
- Tapping a notification opens the right conversation, group or call from a cold start, the background or the foreground, waiting for Face ID first.
- VoiceOver Actions and long-press menus on conversations (timed mute, pin, read/unread, call, video, archive, delete, block, report), on messages (reply, copy, react, read aloud, forward, delete for me, report, show time sent and read), on call participants and on calls. Rotors for unread messages, their messages and my messages.

### Changed
- Version 1.9.0, build 13. Android paused for this release.

## [1.8.0 Android] — 2026-10-23

### Added
- Messages and Calls tabs (Create moved to More > Creator tools), unread badge from the server's unread count.
- Messages: pull to refresh, error state with Retry, 5-second live thread refresh, mark read on open, mark unread, TalkBack announcements for new messages, Sent/Delivered/Read receipts, typing indicator, read-receipt setting synced with the server, new message by @username, offline send queue, drafts, pin, mute, search, reply with quote, copy, share, read aloud with speed, notification center with Mark all read.
- Calls: dial by @username, 45-second ring timeout, failed calls always ended on the server, mute/speaker/camera/end controls, call history with All/Missed filter and Call back, favourites, report a call.
- Report users, messages and calls; block and unblock with a Blocked accounts list.
- Optional biometric/screen-lock app lock (asks on cold launch only).
- Push notifications open the right conversation or call.

### Changed
- Edge-to-edge: removed the deprecated status bar theme attribute, activity 1.10.1 `enableEdgeToEdge()`, and inset padding on full-screen views.
- R8 optimisation stays on (`proguard-android-optimize.txt`, minify and resource shrinking); mapping uploaded with the release.

## [1.8.0 iOS] — 2026-10-23

### Fixed
- Messages inbox showed nothing: the conversation list returns `verified` as 0/1 and the app required true/false, so the whole list failed to decode. Booleans are now decoded leniently.
- Outgoing calls that fail now always send end to the server, so they no longer stay "ringing".

### Added
- Dedicated Messages and Calls tabs (Create moved to More > Creator tools).
- Messages: 5-second live refresh, unread dots and tab badge, read receipts, pin, mute, mark unread, conversation and in-thread search, reply with quote, copy, share, read aloud with speed, drafts, offline send queue, username check, notification center.
- Calls: server call history with call back, missed filter, favorites, ringback with 45-second no-answer end, speaker control, full-screen in-call controls, report a call.
- Blocked accounts list with Unblock.

## [1.7.1 Android] — 2026-10-03

### Added

- Google Play release bundle workflow (`release-aab.yml`): an AAB signed with the Play upload key from
  GitHub secrets, with signer, versionCode and targetSdk checks.
- Release signing reads `ANDROID_UPLOAD_*` environment variables (keystore file or base64) and stays
  unsigned when they are absent.

### Changed

- Android versionCode 8, versionName 1.7.1 (first Google Play upload).

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
