# AI_CHANGELOG.md — Mr. Blindbandit Mobile

Machine-readable history of **AI-assisted** changes to this repository. Update when agents make substantial changes.

## 2026-09-18

### Governance & professionalism
- Added full open-source governance suite: `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `.github/CODEOWNERS`, issue templates, PR template
- Added `AGENTS.md` + this `AI_CHANGELOG.md` for coding-agent context
- Repo topics/description/homepage set via `gh repo edit`
- README professionalism pass: flagship Clerk/LiveKit framing, ChatGPT Sites API host, privacy URL, package IDs

### Flagship 1.5 (PR #14 — `flagship/1.5-clerk-livekit`)
- Clerk auth (Google + email; Apple/Phone off) with store compliance (account deletion, privacy/terms links)
- LiveKit voice & video calls, Connect hub
- Direct messages: data channel, receipts, typing, voice notes, attachments
- Ambient SFX + haptics pickers
- Listen music services hub + Musician Studio / creator tools polish
- CI fixes (Android AGP/lint/Timber, JVM unit-test URI policy, LiveKit publishData API, iOS/Android workflow alignment)
- Store readiness docs (`Config/STORE_COMPLIANCE.md`, integration notes)

### Earlier 2026-09 AI-assisted phases
- Cross-platform creator suite (v1.4): native media tools, accessibility polish, CI unsigned IPA / debug APK artifacts
- Professional README + releasing discipline (`RELEASING.md`)
- Dependabot for Gradle and GitHub Actions

---

*Agents: append dated sections; never paste secret values. Point to commits/PRs when known.*
