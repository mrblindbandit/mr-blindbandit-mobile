# Security Policy

## Supported surfaces

| Surface | Status |
|---|---|
| iOS app (`App/`) | Supported |
| Android app (`Android/`) | Supported |
| CI-produced unsigned IPA / debug APK artifacts | Best-effort (dev only) |
| Backend APIs on **ChatGPT Sites** (`https://mrblindbandit.net`) | Report here if client-triggered; also see website `SECURITY.md` |

## Reporting a vulnerability

**Please do not open a public GitHub Issue for security bugs.**

Email **business@mrblindbandit.net** with:

1. Description of the issue and potential impact
2. Steps to reproduce (PoC if available)
3. Affected platform (iOS/Android), version/build, and OS
4. Your contact details for follow-up

Optional: CC `kheckfinancial@gmail.com` for owner escalation.

We aim to acknowledge reports within **72 hours** and to provide a status update within **7 days**.

## Scope (in)

- Authentication / session issues (Clerk client integration)
- Insecure storage of tokens or PII on device
- LiveKit token misuse or room-join abuse from the client
- Deep-link / URL handling that escalates privilege
- Secret exposure in the binary, repo, or CI logs
- Push-token registration abuse

## Scope (out)

- Denial-of-service without a novel app bug
- Issues only in third-party SDKs (Clerk, LiveKit, etc.) — report upstream; tell us if Blindbandit config worsens them
- Unsigned CI artifacts used outside intended testing

## Secrets

Never commit or paste production secret *values* in Issues/PRs.
Use example files only (`Secrets.local.swift.example`, `local.properties.example`, `Config/Secrets.example`).

## Safe harbor

Good-faith security research that follows this policy and avoids privacy harm,
data destruction, and service disruption is appreciated.
