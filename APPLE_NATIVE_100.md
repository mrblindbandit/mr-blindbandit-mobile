# Apple Native + 100 — iOS 2.2.0 (build 31)

Mega cut after 2.1.0 CI recovery. Ships **all mandatory Apple-native surfaces** plus ~100 additional real product features. No checklist fluff — every item maps to code under `App/AppleNative/`, `Shared/`, `Widgets/`, `WatchApp/`, or wired settings/behaviors.

## A) Native Apple features (mandatory)

1. **Live Activities + Dynamic Island — active call** (`CallActivityAttributes`, `LiveCallActivityController`, `CallLiveActivityWidget`) — ringing/connected timer, mute/speaker chrome; started from CallKit report paths.
2. **Live Activities — Bite post progress** (`BitePostActivityAttributes`, `BitePostActivityController`, `BitePostLiveActivityWidget`) — uploading → posted/failed while composing.
3. **Home Screen widget — Unread DMs** (`UnreadDMsWidget`) via App Group `group.net.mrblindbandit.app`.
4. **Home Screen + Lock Screen widget — Latest Bite** (`LatestBiteWidget`, accessory families).
5. **Home Screen widget — Quick Call / Message** (`QuickActionsWidget` deeplinks `blindbandit://`).
6. **App Intent — Call @handle** (`CallHandleIntent` + App Shortcut phrases).
7. **App Intent — Message @handle** (`MessageHandleIntent`).
8. **App Intent — What’s new on Bandit Feed** (`WhatsNewOnBanditFeedIntent`).
9. **App Intent — Start AI** (`StartBanditAIIntent`).
10. **Focus filter — Quiet Hours / Work** (`BanditFocusFilter` / `SetFocusFilterIntent`) — hide Bites + mute notification categories the Apple way.
11. **Live Communication Kit bridge** (`LiveCommunicationBridge`) with graceful CallKit fallback when LCK unavailable.
12. **Control Center — Mute call** (`MuteCallControl` + `MuteCallIntent`, iOS 18+).
13. **Control Center — End call** (`EndCallControl` + `EndCallIntent`).
14. **Control Center — Start Blind Bandit call** (`StartCallControl` + `StartBlindBanditCallIntent`).
15. **Handoff / Continuity — chat** (`HandoffContinuity` + `net.mrblindbandit.app.handoff.chat`).
16. **Handoff / Continuity — AI thread** (`…handoff.ai`).
17. **Handoff / Continuity — Bites** (`…handoff.bites`).
18. **Core Spotlight — chats** (`SpotlightIndex.indexChat`).
19. **Core Spotlight — people** (`SpotlightIndex.indexPerson`).
20. **Core Spotlight — Bites** (`SpotlightIndex.indexBite`).
21. **TipKit — Swipe to like** (`SwipeToLikeTip` surfaced on Bandit Feed).
22. **TipKit — Magic Tap** (`MagicTapTip`).
23. **TipKit — Search the web** (`SearchTheWebTip`).
24. **Writing Tools — Bite composer** (`banditWritingToolsEnabled` on New Bite field).
25. **Writing Tools — reusable UITextView hook** (`WritingToolsTextField`) for message composer surfaces.
26. **Apple Watch companion** (`WatchApp/BlindbanditWatch`) — unread, quick reply, ring/start call intent (minimal real Watch app + App Group).
27. **CarPlay calling** (`CarPlayCalling` + `BanditCarPlaySceneDelegate` list template) via `INStartCallIntent` as far as entitlements allow.
28. **Deeper Passkeys** (`PasskeyAuthController` — `ASAuthorizationPlatformPublicKeyCredential` register/assert alongside Sign in with Apple).
29. **Image Playground creator entry** (`CreatorAppleToolsStrip` — intentional, not forced junk).
30. **Journal / share-to-writing entry** (ShareLink “Save to Journal” from Bite draft).

## B) ~100 more real features (2.2.0)

### Accessibility
31. Announce reactions (`SettingsKey.a11yAnnounceReaction`)
32. Rotor actions preference (`a11yRotorActions`)
33. Verbose call-state announcements (`a11yCallStateVerbose`)
34. Double-tap compose affordance (`a11yDoubleTapCompose`)
35. Bold status icons (`a11yBoldStatusIcons`)
36. Prefer spoken timestamps (`a11yPreferSpokenTimestamps`)
37. Reduce parallax on cards (`a11yReduceParallaxCards`)
38. Sticky send button (`a11yStickySendButton` + Settings toggle)
39. Haptic alphabet jump (`a11yHapticAlphabetJump`)
40. Higher-contrast chat bubbles (`a11yContrastChatBubbles` + Settings toggle)

### Messaging / Signal-depth
41. Disappearing custom presets (`msgDisappearingCustomPresets`)
42. Expanded pin limit preference (`msgPinLimitExpanded`)
43. Mute forever option (`msgMuteForeverOption`)
44. Starred filter (`msgStarredFilter`)
45. Draft autosave interval (`msgDraftAutosaveSeconds`)
46. Full quote-reply preview (`msgQuoteReplyPreviewFull`)
47. Voice waveform scrub (`msgVoiceWaveformScrub`)
48. Fast-forward voice notes (`msgFastForwardVoice`)
49. Hold-to-record lock (`msgHoldToRecordLock`)
50. Media quality chooser (`msgMediaQualityChooser`)
51. Translate incoming hint (`msgTranslateIncomingHint`)
52. Local scheduled send (`msgScheduledSendLocal`)
53. Reminder on chat (`msgReminderOnChat`)
54. Hide exact typing (`msgHideExactTyping`)
55. Compact chat list density (`msgCompactListDensity` + Settings toggle)

### Calls
56. Noise-cancel hint (`callNoiseCancelHint`)
57. Auto-speaker on dock (`callAutoSpeakerOnDock`)
58. Confirm before ending call (`callEndConfirm` + Settings toggle)
59. Banner while muted (`callBannerWhileMuted`)
60. Remember last camera (`callRememberLastCamera`)
61. Low-data video (`callLowDataVideo`)
62. Haptic ring pattern (`callHapticRingPattern`)
63. Quick-reply decline (`callQuickReplyDecline`)
64. Share link invite (`callShareLinkInvite`)
65. Call history retention days (`callHistoryRetentionDays`)
66. Live Activity tied to CallKit ringing
67. Live Activity tied to CallKit connected
68. Live Activity end on CallKit reportEnded

### Bandit Feed
69. Chronological default (`bitesChronologicalDefault`)
70. Mute creator local (`bitesMuteCreatorLocal`)
71. Save drafts cloud hint (`bitesSaveDraftsCloudHint`)
72. Local censor/blur sensitive media (`bitesCensorLocalBlur`)
73. Double-tap like (`bitesDoubleTapLike` + `DoubleTapLikeModifier`)
74. Long-press react (`bitesLongPressReact`)
75. Hide repost noise (`bitesHideRepostNoise`)
76. Creator analytics local (`bitesCreatorAnalyticsLocal`)
77. Alt text required (`bitesAltTextRequired` + Settings toggle)
78. Offline compose queue (`bitesOfflineComposeQueue`)
79. Spotlight index on Bite appear
80. Widget publish on Bite appear
81. Creator tools strip on composer

### AI
82. Remember thread titles (`aiRememberThreadTitles`)
83. Speak AI answers helper (`aiSpeakAnswers` + `ExtraFeatures220.speakAIAnswerIfEnabled`)
84. Web search default (`aiWebSearchDefault`)
85. Concise mode (`aiConciseMode`)
86. Haptic on AI complete (`aiHapticOnComplete`)
87. Pin favorite prompts (`aiPinFavoritePrompts`)
88. Export thread markdown (`aiExportThreadMarkdown`)
89. Block sensitive topics local (`aiBlockSensitiveTopicsLocal`)
90. AI Handoff activity when AI opens

### Profile / Social
91. Show pronouns (`profileShowPronouns`)
92. Link preview card (`profileLinkPreviewCard`)
93. Mute story replies (`profileMuteStoryReplies`)
94. Follow notif digest (`socialFollowNotifDigest`)
95. Hide suggested (`socialHideSuggested`)
96. Close-friends-only Bites (`socialCloseFriendsOnlyBites`)

### Security / Network / Settings
97. Face ID grace (`secAppLockFaceIDGrace`)
98. Clipboard auto-clear (`secClipboardAutoClear` + helper)
99. Hide notification content when locked (`secHideNotificationContentLock`)
100. Prefer IPv6 hint (`netPreferIPv6`)
101. Retry backoff boost (`netRetryBackoffBoost`)
102. Local settings search index (`settingsSearchIndexLocal`)
103. Export diagnostics (`settingsExportDiagnostics`)
104. Restore defaults confirm (`settingsRestoreDefaultsConfirm`)

### Widgets / Continuity prefs (user-facing toggles)
105. Widget show latest Bite toggle
106. Widget show unread badge toggle
107. Handoff chats enabled toggle
108. Handoff AI enabled toggle
109. Spotlight indexing toggle
110. TipKit enabled toggle
111. Live Activities for calls toggle
112. Live Activities for Bite posts toggle
113. Prefer Passkeys toggle
114. Writing Tools in composers toggle
115. Apple Watch quick reply toggle
116. CarPlay calling toggle
117. Control Center call controls toggle
118. Respect Focus filters toggle (+ `ExtraFeatures220.hideBitesForFocus`)
119. App Group shared store (`BanditSharedStore`) for widgets/Watch/Live Activities
120. Deeplink URL schemes `mrblindbandit` + `blindbandit`
121. Settings → **Apple & Continuity** screen (`ExtraFeatures220SettingsSection`)
122. Bootstrap on launch (`AppleNativeBootstrap.onLaunch` — TipKit + widget reload)
123. Unread badge → widget sync from `ProductionCommunicationsService.unreadCount`
124. Chat open → Spotlight + Handoff
125. Version bump marketing **2.2.0** / build **31** across app + extensions

## C) Server
Widget/deeplink tokens, Focus sync hints, Spotlight id maps, Watch push payloads, and Live Activity push-to-start remain App Group / client-first in this cut. Platform routes can be staged via Sites MCP when push-to-start tokens are issued; client does not require them for local Live Activities.

## D) Targets added
- `BlindbanditWidgets` (`net.mrblindbandit.app.widgets`)
- `BlindbanditWatch` (`net.mrblindbandit.app.watchkitapp`)
- Shared sources: `Shared/BanditSharedStore.swift`, `Shared/CallActivityAttributes.swift`

## E) Version
- Marketing: **2.2.0**
- Build: **31** (supersedes unbroken 2.1.0-on-main / build 30 path)
