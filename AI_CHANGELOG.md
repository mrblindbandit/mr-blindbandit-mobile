## 2026-10-30 — Android 2.0.17 (21): Agora user-account join + call sounds parity

Root cause (verified against production `GET /v1/social/rtc/config` and `worker/platform/rtc-provider.ts`): preferred provider is Agora, tokens are `buildTokenWithUserAccount`, and `rtcFields` returns `rtc_provider` plus nested `rtc` (`app_id`, `channel`, `user_account`, `token`) with `livekit: null`. Android 2.0.16 required a numeric `uid` under `agora`, never sent `rtc_provider=agora`, and on an Agora payload fed the Agora token to LiveKit. Release R8 also did not keep `io.agora.**`, and the manifest removed `FOREGROUND_SERVICE`, so Agora's microphone service cannot start on Android 14+ (targetSdk 36).

- Opt into Agora when the server preference is Agora and credentials are configured; retry on LiveKit if the server rejects the opt-in. Fall back to a LiveKit grant only when one is actually present.
- Join with `joinChannelWithUserAccount`. Log provider choice and Agora error codes without tokens.
- Microphone/camera/mediaPlayback foreground service for the active call. Screen-capture permission stays stripped. Self-managed ConnectionService plus full-screen incoming notification (answer/decline) and the selected ringtone.
- Sounds: Mr. BlindBandit default ringtone, ambient UI cues, howler/reorder from the iOS CAF pack, test tone, announce caller. In-call: audio route, flip camera, keypad, add person, chat, hold, minimize. App-sounds toggle now reaches the player.

Deferred: screen share (media projection stays off), live captions of the remote track, SharePlay, hand raise, iOS Magic Tap.

## 2026-10-26 — Fix in-app Cloud AI → live Gemini `/v1/ai/chat`

Root cause: Cloud AI master toggle defaulted OFF (`UserDefaults.bool` / Android prefs false), while AI Preferences "Allow Cloud AI fallback" defaulted ON but was never read by the escalate path — so the app stayed on-device only even though Sites v153 Gemini chat was live. Secondary: chat used the default 12s API timeout while Gemini can take longer.

- iOS: default Cloud AI ON when unset; wire fallback toggle; 45s chat timeout; send `persona`; surface clear off/error notes; show Gemini ready + last provider; TF **2.2.0 (42)**.
- Android: same default ON + 45s chat timeout + clearer copy; **2.0.15 (19)**.

## 2026-10-26 — Ship dual-RTC Agora build (iOS 2.2.0/40, Android 2.0.13/17)

- Version bump only so TestFlight / Play can pick up merged PR #92 dual-RTC clients.
- Server join latency fix already live Sites v151.

## 2026-10-26 — Dual RTC Agora (iOS + Android)

- Parse `provider` + nested/flat Agora grants from create/join/accept; keep LiveKit nested+flat.
- Route connect/mute/camera/leave through Agora session when `provider=agora`; LiveKit path unchanged.
- SPM `AgoraRtcEngine_iOS` (RtcBasic); Android `io.agora.rtc:full-sdk:4.5.2` + Agora Maven.
- Frame E2EE / Agora video canvas / screen share: follow-up. No App Certificate in client.
- Version bumps left to release workflow.
- See `docs/DUAL_RTC_AGORA.md`.

## 2026-10-26 — Android 2.0.12 (16): phone-feel + join fix + native Bites video

- **Send:** optimistic Sent caption + clear draft immediately; `client_msg_id` + `POST /v1/social/messages/send-ack`; E2EE race ≤350ms; Clerk session token hard 3.5s.
- **Calls:** Dialer keypad; US dial → looping ringback until remote answers; voice-comm progress tones + resume after LiveKit mic.
- **Answer/join:** connect LiveKit immediately (no serial awaitCallFrameKey); late frame key; do not `endOnServer` on transient join failure; clear stuck outbound ringing so Answer works; 12s answer-echo grace.
- **Bites:** native compose (gallery pick → `/v1/media/uploads` or HTTPS URL), in-app VideoView play/pause, optimistic Like — no WebView / external Intent.
- **APIs:** slim inbox + hydrate; call-number get/set/resolve; CallWarmup.
- versionCode **16** / versionName **2.0.12** (2.0.11/15 still in Play review — ship newer).

## 2026-10-26 — TF 2.2.0 (39): phone-feel + native-speed client

- **Ringback:** `connect()` no longer stops US ringback on local LiveKit connect; CallKit `didActivate` resumes progress; progress tones use playAndRecord (fixes LiveKit “recording not supported”).
- **Dialer:** Calls tab front-door keypad; server call-number resolve/set; Profile path kept.
- **Send:** optimistic Sent caption; `client_msg_id` + send-ack; tighter E2EE/plain timeouts; clerk token 3.5s.
- **Inbox:** hard-wire `GET /v1/social/inbox` + hydrate prefetch (Sites bb031a35 live).
- Build **39** / marketing 2.2.0.

## 2026-10-25 — iOS 2.0.10 (29), branch `feat/ios-2010-public-profile-pictures`
- **Bites (P0):** native tab over `/v1/social/newsfeed` + `/v1/social/bites`; composer → posts; like/comment/share/report/delete; disk cache for instant open. `docs/BITES_API.md`.
- **Native Profile:** `/profiles/{handle}/full`, followers/following lists, follow/unfollow optimistic; author tap + People rows.
- **IA:** tabs Chats / Bites / Calls / People / Profile (+ Settings & owner Admin). Groups live under People.
- **Admin (owner @kheck only):** Verify/Unverify via `/v1/social/admin/users/{id}/verify|unverify`, report queue, hide/delete Bite, ban/reinstate, overview stats. `AdminGate` hardcodes owner handle/id until `/me` returns role.
- Keeps 28 voice temp-.m4a + auto-translate + call icons + settings mega.


## 2026-10-26 — TF 2.2.0 (38): Messages timeout soft-recover + US ringback

- **Client (iOS):** Parallel `/me` + inbox bootstrap; never clear ChatCache / set hard `loadError` on transient network (timeout/offline); soft banner + exponential soft-retry; `BlindbanditAPI.softDecodeItems` + thread soft decode; inbox/thread request timeout 20s; ChatCache file protection `completeUntilFirstUserAuthentication`.
- **Server (Sites native-speed batch):** Slim inbox + `since=` incremental sync, call-number resolve/set/directory, multi-thread hydrate, presence/read batch fast paths (see Sites release notes).
- **Calls:** US dial → US ringback (PR #87).
## 2026-10-25 — iOS 2.0.10 (28), branch `feat/ios-2010-public-profile-pictures`
- **Voice play (device proof path):** write decrypted AAC to temp `.m4a` and `AVAudioPlayer(contentsOf:)` (Android MediaPlayer file parity). Session falls back to `.playback` when `.playAndRecord` fails. Keeps 27’s URL resolve / base64url / Bearer /blob / VoiceLog / test tone.
- **Auto-translate E2E:** honor per-chat Security Auto-translate; CloudAI.translate fallback; `LanguageID.detectLoose` for short bubbles.
- **In-call UI:** larger icon grid — mute, speaker, Bluetooth route, camera, flip, screen share, add, keypad, chat, captions, hold, end (VO-labeled).
- Settings hubs: Appearance extras, Advanced & network (proxy/sealed-sender prefs), Blind-first extras, Note to self link. `docs/TYRESE_SIGNAL_COMPETITOR_WISHLIST.md` for server.

## 2026-10-25 — iOS 2.0.10 (27), branch `feat/ios-2010-public-profile-pictures`
- **Voice play root cause fix:** `loadThrowing` now resolves relative attachment URLs against apiBaseURL, accepts base64 *or* base64url keys/nonces, retries 401/403 downloads with Bearer, falls back to `/attachments/{id}/blob`, and accepts plaintext m4a if the blob is already clear. Loud VO "Loading…" / specific failure text. `VoiceLog.lastError` persists across relaunch. Settings → Voice & calls: always-visible Last voice error + **Play test tone** (proves audio session vs network).
- Profile pictures + fat Settings hubs (unchanged from 26) + CallWarmup: rate-limited LiveKit+API TLS warm on Calls/People/chat appear and at placeCall start.
- Build fix: Settings accountSection wrapped in Group (opaque return).

## 2026-10-25 — iOS 2.0.10 (26), branch `feat/ios-2010-public-profile-pictures`
- Public profile pictures: ProfileAvatar + ProfilePictureEditor (Photos/camera), PATCH/PUT social me avatar client; avatars in conversation rows, thread header/info, people, group members, call history, incoming/active call UI, CallKit INImage donate.
- Expanded Settings (Signal/WhatsApp-depth hubs): Chats, Privacy, Notifications, Voice & calls, Accessibility, Data & storage — wired to UserDefaults / NSE App Group / existing services (no stub toggles). Media auto-download + use-less-data, archive muted / keep archived, wallpaper, default disappearing, last-seen local pref, read/typing gates, announce caller, quiet hours, preview style → NSE, earpiece default, live captions default, announce send/delivery, clear caches + sizes, export safety-number help text.
- Photo library usage strings; version 2.0.10 (26). Default ringtone untouched. Server PUT /v1/social/me/avatar may still 404 until site ships — client clears a VoiceOver error and still allows PATCH avatar_url when the CDN URL is known.

## 2026-10-25 — Android 2.0.10 (14), branch `feat/android-parity-210`
- Voice playback fix: shared `VoicePlayback` writes decrypted AAC to a temp `.m4a` before MediaPlayer (in-memory MediaDataSource was broken on many devices). Speeds 1×/1.5×/2×, skip ±5s, listen-once send flag, TalkBack announcements, played-state cache.
- Calling: `installation_id` already on join; **answer-echo ignore** (~8s `joinedAt` / `joiningCallId` + `remoteEnded`) matching iOS 2.0.9; warm call path after bootstrap; prefer Bluetooth headset when speaker off.
- Local-first `ConversationCache` for inbox/thread (ciphertext only) — faster cold start / chat open.
- Public profile avatars: `ProfileAvatar` + `PUT /v1/social/me/avatar` / `PATCH` clear; settings editor.
- Material You dynamic color (Android 12+, high-contrast override); PiP support on MainActivity.
- Notification preview privacy already default-on; settings toggle retained.
- Release: versionCode 14 / 2.0.10; `release-aab.yml` optional Play **internal** upload via `PLAY_SERVICE_ACCOUNT_JSON` + `scripts/upload-play-internal.py` (signed AAB artifact always).
- Gaps / Tyrese: no Play API secret in repo yet (manual Console upload of artifact until secret added); FGS still stripped for Play declaration (no call FGS); group LiveKit frame E2EE rotation; view-once image open; Keystore identity backup UI.

## 2026-10-25 — iOS 2.0.9 (25), branch `feat/ios-209-voice-encryption-calling`
- Voice: MessageRowLabelModifier (no container label on voice rows); activateSession returns Bool + VO; play/resume retry + "Playing"; recorder/send failure announces; hasPlayableVoiceMedia; autoPlay gated by SettingsKey.autoPlayVoice.
- Encryption settings: Restore from iCloud Keychain; forgot dialog prefers iCloud before destructive reset; Encryption + Messages sections in Settings.
- E2EE calling client: BlindbanditAPI.installationID + X-Installation-ID; join/end body installation_id; joinedAt + shouldIgnoreAnswerEcho (~8s); CallKit isAnsweredElsewhereEcho; parseVoIP created_at; awaitCallKey retries + late-key VO; connect announces encryption label. Server gaps (exclude_installation_id, expireRingingCalls caller_id, endCall push-all) documented for Tyrese — client workarounds ship anyway.
- Default ringtone untouched.

## 2026-10-25 — Android direct-call frame encryption and downgrade hardening (PR #66)
- Continued `feat/android-parity-208` from `6226cd1`; retained package/version 2.0.8 (13), Clerk, production API and all prior parity work including #65 routing.
- Added authenticated p256-v1 `call_key` control handling and direct-call LiveKit frame-key wiring with caller-bound key lookup and accessible encryption state. Group frame E2EE/rotation remains incomplete.
- Accepted flat call-grant token/livekit_url fields and rejected non-WSS endpoints.
- Fixed mixed-recipient plaintext downgrade depending on ordering; normalized handles before policy checks. Added security regression tests.
- Code `b82a591`: Android CI 40110833516 passed unit/lint/APK/AAB and four emulator tests; 34 local unit tests passed, local debug/release lint each 0 errors/155 warnings. R8 metadata warnings remain. CI AAB is explicitly unsigned (no signing secrets); physical cross-platform/TalkBack QA remains open. See docs/ANDROID_PARITY.md and docs/ANDROID_RELEASE_QA.md. Draft only: no backend changes, user data removal, merge or publication.


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
