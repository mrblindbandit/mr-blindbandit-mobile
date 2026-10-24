# Android 2.0.11 (15) — full feature cut (2026-10-25)

Branch: `feat/android-full-parity`. Continues after 2.0.10 (14) / PR #69.

## Landed in this cut

### Better AI (iOS parity + Android)
- `AIPersona` Hood/Professional; Hood + Unfiltered only when server handle is `kheck`.
- Deterministic `MusicIntent` before the model; `YouTubeMusicController` (TalkBack / MediaSession / deep link).
- `DeviceActions`: volume, flashlight (Camera permission), brightness (WRITE_SETTINGS), settings panels, open app by name.
- Assistant chat history, persona chips, web search via `GET /v1/ai/search`, existing translate/image/link/transcribe/quota.

### Encryption passcode
- PBKDF2-SHA256 600k + AES-256-GCM → `PUT/GET /v1/keys/backup`.
- Create / restore / forgot-reset UI in Settings (Messages & calls).
- Android identity blob is PKCS8/JSON state — **not** interchangeable with iOS CryptoKit raw export. Same server format and UX.

### View-once
- Removed “not available yet” stub; decrypted view-/listen-once media opens; local open mark after listen-once finishes.

### Group call frame E2EE
- `startGroupCall` fans out the same `call_key` control to members with device keys and configures LiveKit frame crypto when at least one send succeeds.

### Android-only extras
- Quick Settings tile → AI assistant.
- Home widget → Messages (unread count from prefs).
- Extra notification channels: AI, Music, Security (+ existing Messages/Calls).
- Optional notification listener service so MediaSession now-playing can be read (user must enable).

### Version
- `versionName` 2.0.11 / `versionCode` 15.

## Still incomplete / honest limits
- Cross-platform identity restore (iOS ↔ Android) impossible without a shared key encoding; documented.
- Silent Wi‑Fi/BT toggles: settings panels only (Android policy).
- FGS / MEDIA_PROJECTION remain stripped for Play.
- Telecom background calling, full group invite/role UI, on-device LLM: not in this cut.
- Physical-device TalkBack + two-account Android↔iOS call verification still required for certification.

## Validation
- Unit tests: MusicIntent, DeviceActions parse, EncryptionPasscode round-trip (+ existing suite).
- Local: `./gradlew :app:testDebugUnitTest :app:assembleDebug` then CI; signed AAB via `release-aab.yml`.
