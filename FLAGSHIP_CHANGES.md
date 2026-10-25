# Flagship changes — iOS 2.2.0 (build 31)

See **[APPLE_NATIVE_100.md](./APPLE_NATIVE_100.md)** for the Apple-native pack (Live Activities, widgets, App Intents, Focus, LCK, Control Center, Handoff, Spotlight, TipKit, Writing Tools, Watch, CarPlay, Passkeys, creator tools) and the numbered ~100 additional features.

Below is the retained 2.1.0 Bandit Feed / Settings / AI inventory (still shipping).

---

# Prior inventory — iOS 2.1.0 (build 30)

Mega native ship: Bandit Feed, Settings, AI web search, Foundation Models, WebView shell removal, and ~100 meaningful features.

## Numbered features shipped

1. Native Bandit Feed tab (no WKWebView) with live /api/v1/feed preferred + /v1/social/newsfeed fallback
2. Inline What’s on your mind? composer entry on the feed
3. Full-screen Bite composer with Post / Cancel
4. Composer character count (4000) with accessibility label
5. Composer draft autosave to UserDefaults (resume unfinished Bites)
6. Optimistic local post insert after publish
7. Pull-to-refresh on Bandit Feed
8. Disk-cached feed bootstrap for instant open
9. Offline banner when refresh fails but cache exists
10. Empty state with New Bite CTA
11. Error state with Retry
12. Skeleton placeholder loader while first load runs
13. Merge video BanditBites into the text newsfeed
14. Mute author (local) removes their Bites from feed
15. Hide Bite (local) removes one post from feed
16. Saved Bites bookmarks list (device-side)
17. Bookmark / unbookmark from row + toolbar
18. Reactions set: like, love, fire, laugh, wow, sad
19. Reactions confirmation dialog on each Bite
20. Comments sheet via BiteDetailView
21. Load comments from API
22. Post comment with Send + haptic
23. Like / unlike with optimistic UI + rollback
24. Swipe up to like (UISwipeGestureRecognizer) + haptic + flash
25. Swipe down to unlike
26. Settings toggle for swipe-to-like
27. Optional swipe hint caption (VoiceOver-friendly)
28. VoiceOver custom action: Like / Unlike
29. VoiceOver custom action: Open profile
30. VoiceOver custom action: Comment
31. VoiceOver custom action: Share
32. VoiceOver custom action: Save / Unsave
33. VoiceOver custom action: Hide Bite
34. VoiceOver custom action: Mute author
35. Context menu: Like, React, Comment, Save, Hide, Mute, Report, Delete (own)
36. ShareLink for Bite text
37. Verified badge on feed authors
38. Relative timestamps on Bites
39. Dynamic Type capped labels on feed rows
40. Reduce Motion respected on skeleton shimmer
41. Haptics on like / react / send / error
42. Report Bite alert → /v1/social/reports
43. Native Music hub (replaces Website /music/)
44. Native Label hub (replaces Website /label/)
45. Native Community hub (replaces Website /community/)
46. Native About hub (replaces Website /about/)
47. Native Support hub (replaces Website support)
48. Native Media tools hub (replaces Website /media-tools/)
49. More hub Discover: Search people, Notifications, Saved Bites
50. Listen hub site links → Safari Link (no WebView shell)
51. Profile hub Website shells → native hubs
52. Dashboard Music / Media tools → native hubs
53. Settings Profile & account → NativeProfileView (me)
54. People search (DiscoveryAPI with api/v1 + social fallbacks)
55. Notifications inbox native list with empty/error/retry
56. Follow / Unfollow optimistic button (kept + wired)
57. Followers list navigation
58. Following list navigation
59. Share profile (ShareLink)
60. Block profile (local store + announcement)
61. Report profile alert
62. Edit bio native form with char count + PATCH
63. Share my profile on own profile
64. Verified badge display on profiles
65. Message / Call from profile (kept)
66. AI web search via GET /v1/ai/search (Cloud / Brave)
67. WebSearch.needsLiveInfo heuristic auto-injects live results before Foundation Models
68. Search the web accessibility action + menu button in AI chat
69. WebSearchTool kept for on-device tool calling when allowed
70. Settings: Allow AI to search the internet
71. Settings: Prefer on-device Apple Foundation Models
72. Settings: Allow Cloud AI fallback
73. Settings: Speak AI replies (wired to AIVoice)
74. Settings: AI persona modes — Friendly / Blind Bandit / Concise / Coach
75. Persona mode prompt add-on injected into LanguageModelSession instructions
76. Stronger shared AI system prompt (cite links, Blind Bandit awareness, length)
77. AI quick actions: Summarize thread
78. AI quick actions: Rewrite clearer / warmer
79. AI quick actions: Translate (default Cebuano/Tagalog/English/Spanish)
80. AI quick actions: Caption helper
81. AI quick actions sheet component for threads
82. Caption helper preference toggle
83. Default translate language picker
84. Bandit Feed settings section (9 toggles)
85. Clear saved / muted / hidden local feed data
86. Privacy extras: online status, unknown callers, receipts, typing, last seen
87. Notification categories: Bites, comments, mentions, reactions, followers
88. Appearance & language: scheme, language hint, reduce animations, compact/bold feed
89. Security extras: Face ID on open, auto-lock minutes
90. Settings hub links for Feed / AI / Privacy extras / Notif categories / Appearance / Security extras
91. Chat pin / mute helpers (ChatListPrefs) for reuse
92. ChatSearchBar component
93. ThreadMutePinMenu component
94. Typing indicator dots (Reduce Motion aware)
95. Read receipts toggle row component
96. In-call action bar: Mute / Speaker / Camera / End with a11y labels
97. Call history row polish (missed/out/in + relative time)
98. OfflineBanner reusable component with Retry
99. Messages list already ships searchable + pin/mute swipe (kept, no regression)
100. Version bump to 2.1.0 (30) for TestFlight readiness
101. BiteAuthor decodes username + handle for /api/v1/feed
102. BiteItem decodes like_count / comment_count aliases
103. FLAGSHIP_CHANGES.md documents this mega ship

## WebViews removed from core paths

- MoreHub: Music, Label, Community, About, Support → native hubs (Safari Link only for explicit external opens)
- ListenHub: Music/Latest/Browse site → native or Safari Link
- ProfileHub: Music/About/Support → native
- Dashboard: Music/Media tools → native
- Settings: Profile & account → NativeProfileView
- Browser/Website retained only for rare notification deep-links and explicit Safari opens

## AI search path

1. User asks a live/current question (or taps Search the web).
2. `WebSearch.needsLiveInfo` or explicit Search the web prefixes the prompt.
3. `WebSearch.search` → `SecurityAPI.gated(.aiSearch)` → `GET /v1/ai/search?q=` on mrblindbandit.net.
4. Results injected into on-device `LanguageModelSession.streamResponse` when Foundation Models available.
5. Cloud AI fallback still runs via `CloudAI.chat` when escalated / forced / empty.
6. `WebSearchTool` remains available to the on-device tool list when Settings allow it.

## Foundation Models changes

- Stronger shared persona + Blind Bandit / length / cite-links guidance
- `AIPersonaMode` prompt add-on (friend / bandit / concise / coach)
- Prefer-on-device routing note in instructions
- Live web context pre-injected into `streamResponse`
- Search the web entry point alongside Ask the bigger AI
- Existing tools (search chats, draft, translate, music, weather, webSearch, …) retained

## Version

- MARKETING_VERSION 2.1.0 / CURRENT_PROJECT_VERSION 30

## Compile note

Linux box has no full Xcode. Swift sources were syntax-reviewed; full `xcodebuild` must run on macOS CI / a Mac for TestFlight.
