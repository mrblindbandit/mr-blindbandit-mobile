# Release Process — Mr. Blindbandit Mobile

The version shown in the apps, source configuration, GitHub Actions, documentation, pull requests, and downloadable artifacts must always agree.

## Canonical release version

Current release: **1.5**

- iOS: `MARKETING_VERSION = 1.5`
- iOS build: `CURRENT_PROJECT_VERSION = 5`
- Android: `versionName = 1.5.0`
- Android build: `versionCode = 5`

## App Store / Play Store readiness checklist

### Apple App Store

- [ ] Privacy Policy URL: `https://mrblindbandit.net/privacy/`
- [ ] Terms of Use URL: `https://mrblindbandit.net/terms/`
- [ ] Sign in with Apple enabled (capability + entitlement) alongside Google / email
- [ ] Account deletion available in Settings → Delete account (Guideline 5.1.1)
- [ ] Accurate `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`, Bluetooth purpose strings
- [ ] Permissions requested only at call / voice-note / upload time
- [ ] Export compliance: app uses only HTTPS / standard encryption (LiveKit over TLS/DTLS) — answer **No** to proprietary non-exempt encryption if applicable under current Apple guidance for HTTPS-only apps
- [ ] Age rating: content appropriate for music / creator tools (no UGC chat moderation gaps undocumented)
- [ ] App icon 1024×1024 from Blindbandit Records gold logo; 6.7" / 6.5" / 5.5" screenshots for Home, Create, Connect, Listen, Settings
- [ ] No private APIs; no “beta/preview” wording in metadata
- [ ] Review notes: explain Clerk auth, LiveKit demo room, and that call tokens are minted server-side

### Google Play

- [ ] Data safety form: Clerk account identifiers; LiveKit audio/video while in call; FCM tokens; WebView cookies for first-party sign-in
- [ ] Privacy Policy URL in Play Console
- [ ] Account deletion path in-app (Settings) + web
- [ ] Camera / mic / Bluetooth permissions declared with clear in-app rationale
- [ ] Target API 35; 64-bit; no cleartext traffic
- [ ] Feature graphic + screenshots matching gold/black Blindbandit brand
- [ ] Content rating questionnaire completed

### Both

- [ ] Update iOS `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml`
- [ ] Update Android `versionName` / `versionCode` in `Android/app/build.gradle.kts`
- [ ] Update CI artifact names in `.github/workflows/ios.yml` and `android.yml`
- [ ] Update README current-release table and `CHANGELOG.md`
- [ ] Never commit `App/Secrets.local.swift`, `Android/local.properties`, `google-services.json`, or API secrets
- [ ] Run iOS tests + unsigned IPA; Android unit tests + lint + debug APK
- [ ] VoiceOver and TalkBack smoke test on physical devices

## Artifact naming

- iOS: `Mr-Blindbandit-iOS-v1.5-unsigned-IPA` / `Mr-Blindbandit-iOS-v1.5-unsigned.ipa`
- Android: `Mr-Blindbandit-Android-v1.5-debug-APK` / `Mr-Blindbandit-Android-v1.5-debug.apk`

## Security rule

Never commit signing keys, Apple private keys, Firebase server credentials, Clerk **secret** keys, LiveKit **API secrets**, Google OAuth **client secrets**, or other long-lived private credentials.
