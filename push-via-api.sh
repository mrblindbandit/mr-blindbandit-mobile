#!/usr/bin/env bash
# Push flagship 1.5 sources to GitHub as branch flagship/1.5-clerk-livekit and open a PR.
# Prefers: gh auth → clone → copy (excluding secrets) → commit → push → gh pr create.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="${REPO:-mrblindbandit/mr-blindbandit-mobile}"
BRANCH="flagship/1.5-clerk-livekit"
WORKDIR="${WORKDIR:-/tmp/mr-blindbandit-mobile-flagship-$$}"

echo "==> Checking gh auth"
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh is not authenticated. Run: gh auth login" >&2
  exit 1
fi
gh auth status

echo "==> Cloning $REPO to $WORKDIR"
rm -rf "$WORKDIR"
gh repo clone "$REPO" "$WORKDIR"
cd "$WORKDIR"
git fetch origin
git checkout -B "$BRANCH"

echo "==> Syncing files from $ROOT (excluding secrets & VCS)"
# Copy via tar to avoid rsync dependency; preserve .git in WORKDIR
tmp_tar="$(mktemp)"
(
  cd "$ROOT"
  tar --exclude='.git' \
      --exclude='App/Secrets.local.swift' \
      --exclude='Android/local.properties' \
      --exclude='google-services.json' \
      --exclude='GoogleService-Info.plist' \
      --exclude='.gradle' \
      --exclude='build' \
      --exclude='DerivedData' \
      --exclude='dist' \
      --exclude='.DS_Store' \
      -cf "$tmp_tar" .
)
# Remove everything except .git then extract
find "$WORKDIR" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
tar -xf "$tmp_tar" -C "$WORKDIR"
rm -f "$tmp_tar"

# Ensure secrets never land in the clone
rm -f "$WORKDIR/App/Secrets.local.swift" "$WORKDIR/Android/local.properties"

echo "==> Staging and committing"
git add -A
# Double-check secrets not staged
if git diff --cached --name-only | grep -E 'Secrets\.local\.swift$|local\.properties$|google-services\.json$|GoogleService-Info\.plist$' ; then
  echo "ERROR: Refusing to commit secret files" >&2
  exit 1
fi

if git diff --cached --quiet; then
  echo "No changes to commit."
else
  git commit -m "$(cat <<'MSG'
Flagship 1.5: Clerk auth, LiveKit Connect, Listen, store compliance

Ship App Store / Play–ready shell with Clerk (Apple/Google/email) gate,
LiveKit voice/video/chat/voice notes, Listen music services, Musician Studio,
branded gold loaders, accessibility polish, account deletion, privacy/terms,
and version bump to 1.5 (build 5). Secrets remain gitignored.
MSG
)"
fi

echo "==> Pushing $BRANCH"
git push -u origin "$BRANCH"

echo "==> Opening pull request"
PR_URL=$(gh pr create \
  --title "Flagship 1.5 — Clerk, LiveKit, Listen, store compliance" \
  --body "$(cat <<'BODY'
## Summary
- Natural Clerk onboarding: **Continue with Apple**, Google, and email (Guideline 4.8)
- In-app **Delete account** + Privacy Policy / Terms (Guideline 5.1.1)
- LiveKit **voice / video / messaging / voice notes** UI + SDK wiring
- **Listen** hub (Spotify, Apple Music, Amazon, Audiomack, …) + first-party music pages
- IA: Home · Create · Connect · Listen · More; Settings via More
- Musician Studio tools + branded spinning gold Blindbandit Records loaders
- VoiceOver / TalkBack polish; versions **iOS 1.5 (5)** / **Android 1.5.0 (5)**
- Secrets via gitignored local files only (`Config/Secrets.example`)

## Test plan
- [ ] iOS: auth gate → unlock → Connect call/chat/voice note smoke
- [ ] iOS: Sign in with Apple / Google / email paths
- [ ] iOS: Settings → Delete account confirmation
- [ ] Android: same flows + TalkBack labels
- [ ] Confirm `Secrets.local.swift` / `local.properties` not in the PR diff
- [ ] CI green (iOS tests + Android unit/lint)

## Store
See `RELEASING.md` and `Config/STORE_COMPLIANCE.md`.
BODY
)" --base main --head "$BRANCH" 2>/dev/null || true)

if [[ -z "${PR_URL}" ]]; then
  # PR may already exist
  PR_URL=$(gh pr view --json url -q .url 2>/dev/null || gh pr list --head "$BRANCH" --json url -q '.[0].url')
fi

echo "PR: ${PR_URL:-created or already open}"
echo "DONE"
