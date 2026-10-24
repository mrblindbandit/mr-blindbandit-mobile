# Android parity work — 2026-10-24

Reference: main `986372ddaaa0c914c451603ebda4691f1b33aa55`, iOS 2.0.8 (24).
Android baseline: 1.8.0 (12). Work branch: `feat/android-parity-208`.
All checked implementation items still require the verification gates below. This is not a release certification.

## Feature inventory and gaps

| Area | Existing Android | iOS reference and remaining work |
|---|---|---|
| Authentication | Clerk email/Google, session JWT | Preserve existing system; verify device OAuth, refresh, sign-out and deletion |
| Direct messaging | Inbox, polling, typing, receipts, drafts, retry queue, block/report | p256-v1 envelopes, encryption status, signed controls, history restore |
| Groups | Missing native screens | List/create/detail, membership/roles, send/read/typing, reactions, calls |
| Encryption | Transport TLS/WebRTC | P-256 X3DH, HMAC chains, multi-device fanout, one-time prekeys, TOFU, safety numbers |
| Secure storage | Plain preferences for drafts/queue | Android Keystore authenticated encryption, migration without data loss; account isolation |
| Attachments | No native encrypted message attachment workflow | Chunked AES-GCM/Padmé, upload/download, size/digest validation, share/export, view-once |
| Voice messages | No native chat recorder/player | Record, encrypted transport, playback, transcript, TalkBack Play/Pause actions |
| Calls | LiveKit connect, mute/camera/speaker, recents | Incoming lifecycle, permission sequencing, video rendering, group participants/invite, frame E2EE |
| Background calls | FCM tray alert | Android Telecom/foreground call lifecycle needs real-device verification and Play declaration review |
| Notifications | FCM token + local notification | Query routing (#65), group routing, independent pending intents, end-event handling, private previews |
| Cloud AI | Missing | Opt-in chat, translate, image, transcription, link check and quotas on existing /v1/ai routes |
| On-device AI | Missing | Android capability detection and actual supported models; do not label heuristics as an LLM |
| Speech/captions | TTS read-aloud | Speech recognition permission/lifecycle; distinguish system service from offline availability; no remote-call caption claim |
| Translation | Missing | Opt-in cloud translation; offline language-pack parity requires Android model provider |
| Security/privacy | App biometric lock, deletion, content filter, backup disabled | Per-chat disappearing/view-once, key verification/export/recovery, preview controls, relay-only |
| Profiles | Web account + server identity | Native edit/search/directory, verified states, device management |
| Creator/music | Native creator tools + Listen + Chronicle | Inventory each iOS-only media utility, speech/image/music intent and file export flow |
| Sounds | Existing MP3 library | New Mr. BlindBandit ringtones and ambient selections, native formats |
| Accessibility | TalkBack row actions, TTS, large text, contrast | New screens need labels, headings, status announcements, focus/error recovery, 200% font device QA |

## Work checklist

- [x] Read AI_CHANGELOG, AGENTS, README, Android README, CONTRIBUTING, SECURITY, RELEASING and Config docs.
- [x] Inspect remote branches and all open PR metadata; latest iOS product changes are already merged into main.
- [x] Review #65: query-route fix is relevant; extend with tests and trusted-host validation.
- [ ] Implement missing features and update this checklist with exact delivered scope.
- [ ] Compile debug/release, unit tests, lintDebug/lintRelease and instrumentation.
- [ ] Cross-platform p256-v1 vectors; out-of-order, replay, tamper, key-change, multi-device tests.
- [ ] Authenticated two-account Android/iOS messaging, attachment and call integration.
- [ ] TalkBack physical-device test, background/locked/killed app, denied permissions, token rotation.
- [ ] Confirm versionCode exceeds highest Play upload (baseline in source is 12).
- [ ] Build AAB using existing authorized upload-key workflow, validate manifest and signer.
- [ ] Owner approval before Google Play publication. Never merge untested work.

No server changes are authorized by this implementation unless separately documented as necessary; none have been made.

## Implemented in this branch (verification pending)

- Trusted first-party and custom-scheme call/DM/group routes; includes #65 query forms and tests.
- FCM data-payload terminal call handling, collision-resistant notification intents, private previews.
- Microphone answer sequencing, per-installation call join/header, decline fallback and transient /end retries.
- Native group list/create/read/send, members, add/remove, rename, leave, silent sends and reactions.
- Account-scoped Keystore encrypted key/session/message state; migrated encrypted drafts/offline queue.
- p256-v1 P-256 X3DH, authenticated prekeys, device fanout, incoming chain/skipped keys and replay rejection.
- Fresh outbound ephemeral session for each message (compatible n=0), rather than reusing an outbound chain.
- Safety-number display and key-change blocking. A changed identity requires a future verified reset UI; it cannot be silently approved here.
- AES-GCM chunked attachments, Padmé size padding and hash verification, native file picker/export.
- AAC voice recording and in-memory playback, explicit Play/Pause controls for TalkBack.
- Native opt-in cloud chat, translation, image generation, link check and quota view.
- Optional Android 12+ on-device speech recognition. No network speech fallback and no remote-call audio capture.
- LiveKit local/remote video rendering; call timing continues across tab changes.

## Remaining implementation before parity/release

- Android Telecom/foreground-service integration for reliable locked/background calls, with device and Play-policy validation.
- LiveKit frame E2EE / `call_key` handling, screen share and phone-audio capture.
- Group call UI/invite/role/join-request/invite-link management and complete group typing/receipt states.
- Passcode-based key backup/restore, key rotation/revocation UI, session management UI and cross-device history recovery.
- Signed deletion/edit controls, relay-only queues, disappearing chat settings, view-once consumption, polls, scheduling and complete reaction rendering.
- A bundled/general on-device LLM and offline translation models; cloud transcription and summary UI.
- Native profile/directory/verification parity and remaining iOS-specific creator/media utilities.
- New 2.0.8 ringtones and all ambient options, call-quality/audio routing UI parity.
- Full physical-device TalkBack, Android/iOS account-to-account and release-signer verification.

### Backend compatibility note

No backend has been changed. For Android notification privacy and terminal call events to work while backgrounded, FCM must send **data-only** payloads. An FCM `notification` object is displayed directly by Firebase while the app is backgrounded, bypassing client preview filtering. Verify this existing server behavior before release; propose an Android-only data-payload change if needed. Do not claim client redaction can override Firebase's automatic tray display.
