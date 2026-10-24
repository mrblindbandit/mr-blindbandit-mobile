## 2026-10-25 — iOS 2.0.9 (25), branch `feat/ios-209-voice-encryption-calling`
- Voice: MessageRowLabelModifier (no container label on voice rows); activateSession returns Bool + VO; play/resume retry + "Playing"; recorder/send failure announces; hasPlayableVoiceMedia; autoPlay gated by SettingsKey.autoPlayVoice.
- Encryption settings: Restore from iCloud Keychain; forgot dialog prefers iCloud before destructive reset; Encryption + Messages sections in Settings.
- E2EE calling client: BlindbanditAPI.installationID + X-Installation-ID; join/end body installation_id; joinedAt + shouldIgnoreAnswerEcho (~8s); CallKit isAnsweredElsewhereEcho; parseVoIP created_at; awaitCallKey retries + late-key VO; connect announces encryption label. Server gaps (exclude_installation_id, expireRingingCalls caller_id, endCall push-all) documented for Tyrese — client workarounds ship anyway.
- Default ringtone untouched.

## 2026-10-24 — iOS 2.0.7 (22), branch `feat/ios-207-app-fixes`
- App-only: notification preview privacy (NSE + App Group), group VoiceOver/silent/schedule/optimistic/cache, live-caption speech-fail announce, screen-share DRM VO note, third ringtone CAF, AI gate audit (no code path change). Server batches still Tyrese.

# AI_CHANGELOG.md

> **For other AIs:** this is the work-history file. Also read `AGENTS.md`. Never commit secrets.

Cross-links:
- Website: https://github.com/mrblindbandit/mr-blindbandit-website/blob/main/AI_CHANGELOG.md
- Mobile: https://github.com/mrblindbandit/mr-blindbandit-mobile/blob/main/AI_CHANGELOG.md
- Bio/profile: https://github.com/mrblindbandit/mrblindbandit/blob/main/AI_CHANGELOG.md
- Pages: https://github.com/mrblindbandit/mrblindbandit.github.io/blob/main/AI_CHANGELOG.md

---

## 2026-10-23 — iOS 1.9.0 (13), PR #47
- New files: CallKitManager.swift (CallKit/PushKit/INStartCallIntent, caller identity), CallScreens.swift (incoming + active grid call UI), CallEngineTypes.swift, CallsGroupsAPI.swift, GroupsAndPeople.swift, PushRoute.swift (pure push parser plus PendingRouter queue), AppTests/Release190Tests.swift.
- The LiveKit audio session is handed to CallKit (auto-config off; engine availability switches in didActivate/didDeactivate).
- Mute timers, archive, delete-for-me and reactions are device-local (LocalComms) until the server routes in /workspace/site-ai-prompt-190-addendum.md exist.
- The app-switcher name scrambling was requested and then cancelled. It was not shipped, and the "Content hidden" behaviour is unchanged.
- Android was not touched (paused). See the PR description for the Android TODO list.


## 2026-10-23 — Android 1.8.0 (12) Messages and Calls tabs (Grok Bot, branch `feat/android-calls-messages`)

- Port of iOS 1.8.0. New connect/: Lenient.kt, CommsModels.kt, LocalComms.kt, Announcer.kt, MessagesScreen.kt, CallsScreen.kt, CommsUi.kt, CommsSettings.kt; ConnectScreens/ConnectCompatibility removed.
- MainActivity is now a FragmentActivity (BiometricPrompt). Push extras conversation_id/call_id route in-app.
- Mark unread is local only (no server route; /messages/{id}/unread returns 404).

## 2026-10-23 — iOS 1.8.0 (12) Messages and Calls tabs (Grok Bot, branch `feat/ios-calls-messages`)

- Missing DM to @kheck: `GET /v1/social/messages` returns `other.verified` as integer 0; `Bool?` threw a type mismatch and the inbox decode failed. Server data was correct; no data fix. Added `FlexibleBool`.
- New: App/CommsTabs.swift, App/CommsModels.swift. Uses /messages/{id}/read, /calls/history, /blocks, DELETE /profiles/{h}/block, /notifications.
- Fastlane waits for processing and attaches fastlane/WhatToTest.txt.

## 2026-09-27 — Store listing and compliance pass (Grok Bot, branch `store/listing-compliance-2026`)

- Store name "Mr. BlindBandit Mobile"; home-screen label "BlindBandit" on both platforms (launchers truncate longer labels).
- iOS sign-in buttons now follow the providers enabled in Clerk (Guideline 4.8): Apple only when enabled, Google only alongside Apple. Clerk production currently enables Google only, so iOS shows email only until the owner enables Apple.
- On-device objectionable-language filter for messages (Settings > Safety, on by default) plus safety links (Guideline 1.2 / Play UGC).
- In-app browser sends Global Privacy Control so the site keeps ads and analytics off inside the apps.
- Fixed broken links: `/store/` (404) replaced by Blindbandit Records `/label/`; OkHttp license URL.
- Privacy manifest adds Other User Content. Usage strings use the store name.
- Debug-only store screenshot mode and `.github/workflows/store-screenshots.yml` (Android 1080x1920, iPhone 6.9-inch 1320x2868).

---

## 2026-09-27 — Installable build artifacts (Grok Bot, branch `ci/build-artifacts`)

- Added `.github/workflows/build-artifacts.yml` (workflow_dispatch): Android release APK signed with a throwaway debug keystore (sideloadable) and an unsigned iOS IPA built for `generic/platform=iOS`.
- The APK job also emits an arm64-v8a-only APK (~35 MB vs ~67 MB universal) so it fits simple upload/sideload paths; both are signed with the same per-run debug key.
- `build-unsigned.sh` now targets `generic/platform=iOS`, checks the `.app` actually exists, and cleans `dist/Payload` after zipping.
- Local audit: Android unit tests, lint and debug/release assembles pass; placeholder gate passes. No app code changes were needed.

---

## 2026-09-26 — Store-ready revamp, v1.7 (Grok Bot, branch `revamp/store-ready`)

- Audited both apps against the App Store Review Guidelines and Google Play policy. Found that `/v1/mobile-native/*` returns 404 in production and that the API wraps responses in `{success,data}`, so calls, messages and deletion were broken.
- Rewired both apps to `/v1/social/*` and `/v1/privacy/delete` (shapes verified against `worker/platform/social.ts`).
- Added report/block, full Settings, a design system, in-context permissions, push registration and iOS video rendering.
- Removed developer screens, the keypad, and unused permissions.
- CI: placeholder gate, Android emulator tests, signed AAB when secrets exist, iOS simulator tests, and a secrets-gated archive.
- Clerk was not changed. The dashboard steps are in RELEASING.md.

---

## 2026-09-18 — Full Blindbandit GitHub / product day (Grok Bot)

### YouTube (@MrBlindbandit)
- Overnight SEO, cinematic thumbs, playlists, channel settings, end screens/cards
- Viral Short (Runway stills + Clairvoyant Castle + SFX) uploaded; MP4 to business@mrblindbandit.net

### GitHub account
- Login as mrblindbandit via Google; Cursor SCM connected
- Vulnerability alerts + automated security fixes enabled on all four repos
- Marketplace app install (e.g. Renovate) **blocked by GitHub sudo-mode 2FA** — pending Mobile approval

### Mobile (`mr-blindbandit-mobile`)
- Flagship iOS+Android: Clerk (email+Google; Apple off) + LiveKit calls/DMs
- DMs: attachments, hold voice notes, receipts, typing; SFX/haptics/visuals
- Privacy → mrblindbandit.net/privacy; PR #14 / v1.5 CI hardening

### Website (`mr-blindbandit-website`) — production = **ChatGPT Sites** (mrblindbandit.net)
- Social `/mobile`, Label Portal/Social Admin, API `/api/v1`, LiveKit, push wiring
- Migrations **0007** + **0008**; legal master package; thin shells → 0
- Public repo + Pages mirror https://mrblindbandit.github.io/
- Governance suite + AGENTS.md / AI_CHANGELOG.md / CI workflows
- Drive zip after quota fix

### Bio repo (`mrblindbandit`) + Pages (`mrblindbandit.github.io`)
- Professionalization, AGENTS.md, AI_CHANGELOG.md, topics/security alerts

### Still pending often
- FCM service-account JSON + APNs on ChatGPT Sites secrets
- Marketplace apps after user completes GitHub Mobile sudo 2FA

---

## 2026-09-18 — Mobile v1.5 release integration (ChatGPT)

- Integrated the flagship 1.5 iOS + Android branch with the current `main` governance/Dependabot files without committing secrets.
- Preserved the v1.5 CI workflows for iOS 1.5 (build 5) unsigned IPA and Android 1.5.0 (versionCode 5) debug APK.
- PR #14 CI was green for both iOS and Android before release integration.
- Release artifacts remain development builds: iOS unsigned IPA and Android debug APK; store signing/provisioning is separate.

---

## 2026-09-18 — Production public mobile configuration (ChatGPT)

- Added client-safe production defaults for the Clerk publishable key, LiveKit WebSocket endpoint, and Google OAuth client ID on iOS and Android.
- Kept local/environment overrides available for development and CI.
- Deliberately kept LiveKit participant JWTs, Clerk secret keys, LiveKit API credentials, Google OAuth client secret, VAPID private key, and push service credentials out of the mobile source and binaries.
- LiveKit production calls remain designed to obtain short-lived participant tokens from the server; scaffold tokens remain local-only.

---

*Append dated sections after substantial AI-assisted work.*

## 2026-10-24 — Android parity development (draft, not a release)

- Reference inspected: iOS 2.0.8 (24), main 986372d, all remote refs and open PR metadata including #65.
- Dedicated branch feat/android-parity-208; package net.mrblindbandit.app retained, candidate Android 2.0.8 (13).
- Native groups, p256-v1 encryption and Keystore local storage, encrypted file/voice messages, opt-in Cloud AI, optional on-device speech, video rendering and call/push fixes.
- Includes the intent of PR #65, extended with host validation and regression tests. No main merge or Play publication.
- Exact delivered/remaining scope, interoperability differences and release blockers: docs/ANDROID_PARITY.md.
- No backend, signing identity or account/conversation data reset. A production-ready artifact requires all documented release gates.


## 2026-10-24 — Continue Android parity PR #66 (ChatGPT)
- Preserve the existing parity branch and production package/auth/backend. PR remains draft; do not merge as complete parity.
- Connect encrypted group file/voice workflows, group typing and role controls, authenticated people picker.
- Add explicit cloud summaries and audio transcription, caption lifecycle handling, full current ringtone/ambient asset pack with native preview lifecycle.
- Extend p256-v1 receive/interoperability validation. See docs/ANDROID_PARITY.md for exact remaining gaps and release gates.
- No backend changes, new production signing identity, merge or Google Play publication.
