# AGENTS.md — Mr. Blindbandit Mobile

Instructions for coding agents (Cursor, ChatGPT, Copilot, Claude, etc.) working in this repository.

## What this repo is

Native **iOS + Android** flagship apps for the Blindbandit / Mr. Blindbandit ecosystem:

- iOS (SwiftUI) under `App/` — package-ish: `net.mrblindbandit.privateapp` family
- Android (Kotlin) under `Android/` — application id: `net.mrblindbandit.app`
- CI workflows under `.github/workflows/` (`ios.yml`, `android.yml`)
- Flagship 1.5 work (Clerk + LiveKit + DMs/voice notes) lands via PR [#14](https://github.com/mrblindbandit/mr-blindbandit-mobile/pull/14) on branch `flagship/1.5-clerk-livekit`

## Production host (critical)

Backend / website APIs run on **ChatGPT Sites (OpenAI Sites)** at **https://mrblindbandit.net** — **not** “hosted on Cloudflare” as the product host.

- Privacy: https://mrblindbandit.net/privacy
- Terms / legal: https://mrblindbandit.net/ (legal pages)
- GitHub Pages (`https://mrblindbandit.github.io/`) is a **static mirror** only — no Worker/D1/Clerk runtime there

## Related repos

| Repo | Role |
|---|---|
| `mrblindbandit/mr-blindbandit-mobile` | This repo (iOS + Android) |
| `mrblindbandit/mr-blindbandit-website` | Website + Worker/API + D1 source |
| `mrblindbandit/mrblindbandit.github.io` | Static Pages mirror |
| `mrblindbandit/mrblindbandit` | GitHub profile README |

## Auth & integrations

- **Clerk**: email + Google on; **Apple Sign In off** for now (no Apple Developer account yet — keep feature-flagged off)
- **LiveKit**: voice/video/chat/voice notes — tokens minted by website Worker, never hardcode secrets in the app
- **Push**: APNs (iOS) + FCM (Android) scaffolds — production credentials stay server-side / CI secrets
- Publishable Clerk keys only in-app; secrets in gitignored local files (`Secrets.local.swift`, `local.properties`, etc.)

## Hard rules

1. Never commit secrets (Clerk `sk_`, LiveKit API secrets, PEMs, `google-services.json` with private keys, signing keystores)
2. Do not break existing CI workflows unless intentionally updating them
3. Prefer additive, reviewable changes; keep accessibility (VoiceOver / TalkBack) intact
4. Link privacy/terms to `mrblindbandit.net` — do not invent alternate legal URLs
5. Prefer updating `AI_CHANGELOG.md` when you make substantial AI-assisted changes
6. If OAuth rejects workflow-scope pushes, put YAML under `docs/github-workflows/` instead of forcing `.github/workflows/`

## Read next

- `README.md` — overview + release table
- `RELEASING.md` — version discipline
- `CHANGELOG.md` — shipped history
- `AI_CHANGELOG.md` — AI-assisted change log
- `SECURITY.md` — vulnerability reporting
- Flagship notes (when present on branch): `FLAGSHIP_CHANGES.md`, `Config/STORE_COMPLIANCE.md`, `Config/INTEGRATION_NOTES.md`

## Contact

business@mrblindbandit.net
