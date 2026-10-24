# Tyrese — Signal-competitor server wishlist (give to Tyrese)

Client cut **iOS/Android 2.0.10** ships local/UI for many of these. Hard dependencies that need **site/API** work are listed first. Prefer stable JSON contracts + feature flags so mobile can soft-fail when a route is still 404.

## P0 — already hurting users

1. **Attachments / voice download**
   - Absolute CDN or API URLs in message media (never relative-only).
   - Authenticated `GET /v1/social/attachments/{id}` + `/blob` with Bearer; 401 must not look like “missing feature”.
   - Consistent key encoding: prefer **base64url** for `key` / `nonce` / `sha256` / `wrapped_key`; document both if dual.
   - Range requests optional; Content-Type `audio/mp4` for voice.

2. **Auto-translate pipeline**
   - Harden `POST /v1/ai/translate` `{text, source?, target}` → `{translation}` (ceb/tl/en first).
   - Quota + clear error body when model cold.
   - Optional: server-side language detect endpoint for short messages.

3. **Calling**
   - `exclude_installation_id` (or equivalent) so the caller’s other devices don’t ring.
   - Reliable `/end` + ring cancel fanout; ignore stale invites client-side already exists — server should stop re-pushing ended calls.
   - LiveKit token mint latency: cache/warm path; return region hint.

## P1 — Signal parity (privacy / metadata)

4. **Sealed sender / metadata reduction** — delivery envelopes that don’t reveal social graph to the store-and-forward hop beyond ciphertext size.
5. **Disappearing messages** — server enforce TTL delete after `disappearing_seconds`; sync tombstones to all devices.
6. **View-once / listen-once** — one-time open receipt; server refuses second fetch of ciphertext blob.
7. **Safety numbers** — already partly client; ensure identity key change push + `GET` fingerprint by handle is durable.
8. **Username-only discovery** — no phone graph; rate-limit handle search; block enumeration.
9. **Message requests** — first DM from non-contact lands in Requests; accept/block/report APIs.
10. **Block / report** — `POST /v1/social/block`, `/report` with reason codes; hide from search.

## P1 — product features needing server

11. **Profile avatars** — `PUT /v1/social/me/avatar` (multipart or URL) + CDN; `avatar_url` on conversation/other/call payloads (client already paints when present).
12. **Link previews** — optional server unfurl with SSRF guards; honor `block_link_previews` / hide-previews prefs.
13. **Screenshot notify** — if feasible on mobile OS limits: event channel when peer screenshots (best-effort).
14. **Pin / mute / custom notif per chat** — sync across devices (`pinned`, `muted_until`, `notif_sound`).
15. **Polls / reactions** — finalize group E2EE frames for reaction + poll vote fanout.
16. **Stories / status** — 24h ephemeral posts if lightweight; otherwise skip.
17. **Group E2EE** — sender keys / ratchet for groups; admin policy frames (`allow_ai`, slow mode) already partially flat-decoded on iOS.
18. **Push** — rich NSE payloads with preview privacy flags; collapse IDs for call cancel; Android FCM data-only for CallKit-class urgency where possible.
19. **Receipts** — delivered/read with privacy gates; typing indicators already gated client-side.

## P2 — blind-first differentiators (server optional)

20. **Describe-image / OCR** — keep on-device; optional cloud assist for ceb/tl captions.
21. **Live captions storage** — optional post-call transcript blob for the user’s own archive only.
22. **Proxy/Tor** — document recommended Orbot SOCKS; no special server needed if TLS to API works through SOCKS.
23. **Missed-call callback deep link** — push carries `call_back_handle`.

## Contract notes for mobile

- Feature flags via existing `ServerFeatures` / soft 404 probing — **do not** gate attachment download behind a sticky “missing” flag (404 on `/blob` must stay soft).
- Version every breaking media field (`wrapped_key`, etc.).
- Prefer idempotent POSTs for translate / report / block.

## Already shipped on clients (2.0.10) waiting on you

- Avatar UI + PATCH/PUT client
- Voice download Bearer + relative URL resolve + base64url keys + `/blob` fallback
- Cloud translate fallback when Apple Translation / Apple Intelligence unavailable
- Sealed-sender / screenshot / proxy **prefs** stored locally until APIs exist
- Call warm (LiveKit + API TLS) + voice-processing left on for AEC

When a row above ships, ping mobile with the route + sample JSON — we’ll flip the soft probes to hard support and cut a store build.
