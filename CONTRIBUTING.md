# Contributing to Mr. Blindbandit Mobile

Thanks for your interest. This is the **iOS + Android flagship** for Blindbandit Records. Backend APIs live on **ChatGPT Sites** at `mrblindbandit.net`.

## Before you start

1. Read `README.md` and `AGENTS.md`
2. Read `SECURITY.md` — never open public issues for vulns
3. Do **not** commit secrets (signing keys, Clerk secret keys, LiveKit secrets, PEMs)

## Ways to help

- Bug reports (non-security) via GitHub Issues
- Accessibility improvements (VoiceOver / TalkBack)
- Documentation clarity
- Small, focused pull requests

Large product changes (auth model, messaging protocol, store compliance) should be discussed in an Issue first. Flagship 1.5 work tracks PR [#14](https://github.com/mrblindbandit/mr-blindbandit-mobile/pull/14).

## Development setup

```bash
git clone https://github.com/mrblindbandit/mr-blindbandit-mobile.git
cd mr-blindbandit-mobile
# iOS: open / generate Xcode project from project.yml (XcodeGen)
# Android: open Android/ in Android Studio; copy local.properties.example
```

Copy example secret stubs only — never commit real values.

## Pull request checklist

- [ ] No secrets, keystores, PEMs, or service-account JSON
- [ ] iOS and/or Android CI considered
- [ ] Accessibility labels preserved or improved
- [ ] Privacy/terms still point to `https://mrblindbandit.net/privacy` (and related legal URLs)
- [ ] Docs updated if release version or integrations change
- [ ] Hosting language refers to **ChatGPT Sites** for the website/API host

## Commit style

Prefer clear, present-tense summaries:

- `Fix Android LiveKit publishData API usage`
- `Document Clerk Apple-off store compliance`
- `Improve VoiceOver labels on Connect hub`

## Code owners

See `.github/CODEOWNERS`.

## License

By contributing, you agree your contributions are assigned to / licensed under the repository `LICENSE` (proprietary Blindbandit Records terms) unless otherwise agreed in writing.
