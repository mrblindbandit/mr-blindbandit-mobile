# AGENTS.md — Blindbandit Mobile (iOS + Android)

> **Other AIs:** read [`AI_CHANGELOG.md`](./AI_CHANGELOG.md) first, then this file.

## Mission

You have **broad authority** to maintain this flagship iOS/Android communications + music app: Clerk auth, LiveKit calls/DMs, UI polish, accessibility (VoiceOver/TalkBack), haptics/SFX, store compliance, CI, and docs. Act like a staff mobile engineer for Blindbandit Records.

**Backend / website production:** **ChatGPT Sites** — https://mrblindbandit.net (API `/api/v1`).  
Privacy: https://mrblindbandit.net/privacy

## Broad access (you MAY)

- Edit `App/` (iOS/SwiftUI) and `Android/` (Kotlin/Compose)
- Fix CI, dependencies, LiveKit/Clerk integration issues
- Add features that fit a flagship messenger + musician toolkit
- Update README, governance, `AI_CHANGELOG.md`, store compliance docs
- Keep packages aligned: Android `net.mrblindbandit.app` (and iOS bundle as configured)

## Hard rails (you MUST NOT)

1. **Never commit secrets** — `Secrets.local.swift`, `local.properties` values, API keys, google-services with private keys, `.p8`, service accounts
2. **Never enable Sign in with Apple** unless the owner explicitly asks (no Apple Developer yet historically)
3. **Never strip accessibility** or ship beta-looking broken auth flows
4. **Never force-push `main`** or rewrite published release history carelessly
5. **Never paste production secrets** into Issues/PRs/chat
6. Breaking store policy (privacy nutrition, permissions without purpose) requires human confirmation

## Quality bar

- Flagship polish: no “beta” feel; branded loaders/visuals when touching UI
- Calls/DMs must remain testable (receipts, typing, voice notes patterns)
- Prefer fixing CI over disabling checks long-term
- Document env/setup in example files only

## Related

- Website: `mrblindbandit/mr-blindbandit-website`
- Pages mirror: `mrblindbandit/mrblindbandit.github.io`

Contact: business@mrblindbandit.net
