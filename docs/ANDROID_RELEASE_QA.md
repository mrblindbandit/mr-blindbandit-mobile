# Android 2.0.8 release verification

Package: `net.mrblindbandit.app`. Candidate versionCode: `13`.
This checklist is a release gate, not evidence that the scenarios have passed.

## Required test setup

- Existing Play-installed Android 1.8.0 with seeded conversations, drafts and settings; retain its data.
- Physical Android device with TalkBack and an iPhone running the current iOS build.
- Two owner-approved test accounts; a third device for multi-device delivery and answering elsewhere.
- Firebase delivery to the test installation and production Clerk/API access. Use existing authenticated sessions or the approved test-secret mechanism; never paste credentials into source or PRs.
- Existing authorized upload key in the release workflow and the expected upload certificate fingerprint from Play App Integrity.

## Device and interoperability matrix

Every row below is **not run** until evidence is attached. Emulator settings/storage tests do not substitute for these checks.

| Scenario | Required result |
|---|---|
| Upgrade existing Play installation | Same package and compatible signer; accounts/conversations/settings retained; no uninstall or clear-data step |
| Auth | Email/Google login, verification, expired-token refresh, sign-out/account switch and account deletion work; no prior account data shown |
| First key setup | Registration succeeds with production wire fields; retry after offline failure; prekeys replenish |
| Android → iOS and iOS → Android DM | Text decodes, correct sender/thread, receipts and typing update; E2EE status accurately reflects transport |
| Multi-device messaging | Every registered intended device can decrypt; unavailable/revoked device handling verified; identity change blocks silently trusting a replacement |
| Encrypted group text/media | Current members receive; excluded/removed members do not get future keys; role failures and concurrent membership changes recover visibly |
| Mixed legacy group | A missing-key member cannot downgrade an already encrypted recipient; user receives an actionable error |
| Files/voice | File hash/size validation, recording permission denial, playback, cancellation, save/export and TalkBack actions work both directions |
| Direct audio/video calls | Both directions decode audio/video with frame encryption; screen label matches actual encryption state; no plaintext key transmission |
| Incoming call lifecycle | Foreground, background, locked and process-dead behavior; answer, decline, timeout and caller cancellation; mic/camera permission denial |
| Multiple devices | Answering one device ends ringing elsewhere without ending the answered call; duplicate/stale invites cannot resurrect ended calls |
| Calls under interruption | Network loss/rejoin, Bluetooth/headset changes, screen lock, tab switch, remote hangup and server-end retry recover without ghost ringing |
| Push | DM/group/call routes, private previews, FCM token rotation and logout deregistration; test data-only payloads while backgrounded |
| Cloud AI | Explicit consent, quota/errors, chat/image/summary/transcription/translation; no automatic upload of private chats |
| On-device captions | Supported/unsupported device behavior, denied mic permission, background stop and recognizer failure; no claim of remote-call/offline LLM support |
| TalkBack | Reading/focus order, labelled controls, errors/status, message actions, file/voice operations; 200% font, narrow screen and rotation |
| Privacy/security | Preview settings, biometric lock, filtering, block/report, account switching, no sensitive logs; secure state unavailable after uninstall as documented |

## Before Play publication

1. Finish the remaining implementation in `ANDROID_PARITY.md`, including group frame E2EE, background calling, recovery, advanced chat and remaining AI/profile/creator parity.
2. Pass the current commit's unit, lint, compile and emulator CI gates; review toolchain/R8 warnings and dependency compatibility.
3. Complete the matrix above with device/build identifiers and observed results. Fix failures and rerun affected checks.
4. Check the maximum versionCode across all Play tracks and prior uploads. Increase `13` if necessary; keep `net.mrblindbandit.app`.
5. Run `.github/workflows/release-aab.yml` on the approved release revision using the existing upload-key secrets. Never generate a replacement production identity.
6. Verify bundle package, version, target SDK, signature and expected upload certificate fingerprint. Preserve the AAB and SHA-256 digest.
7. Update Play Data safety, permission declarations, privacy text, release notes and screenshots to match actual behavior.
8. Obtain the owner's explicit Google Play publication approval. Until then, do not publish.
