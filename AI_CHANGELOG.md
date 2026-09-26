# AI_CHANGELOG.md

> **For other AIs:** this is the work-history file. Also read `AGENTS.md`. Never commit secrets.

Cross-links:
- Website: https://github.com/mrblindbandit/mr-blindbandit-website/blob/main/AI_CHANGELOG.md
- Mobile: https://github.com/mrblindbandit/mr-blindbandit-mobile/blob/main/AI_CHANGELOG.md
- Bio/profile: https://github.com/mrblindbandit/mrblindbandit/blob/main/AI_CHANGELOG.md
- Pages: https://github.com/mrblindbandit/mrblindbandit.github.io/blob/main/AI_CHANGELOG.md

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
