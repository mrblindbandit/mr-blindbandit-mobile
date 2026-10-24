# Mr. BlindBandit Mobile: Server Wishlist for a Signal-Class Messenger

Prepared for Tyrese. Each item lists What, Why, and an Acceptance check. Items are grouped by area; numbering is for reference in discussion.

## 1. Calls: Signaling Correctness

### 1.1 Exclude answering installation on answer fan-out
- **What:** When a call is answered, broadcast `call.answered` to all of the callee's other installations except the one that answered (`exclude_installation_id`).
- **Why:** Prevents the answering device from tearing down its own session and stops other devices from ringing.
- **Acceptance:** Answer on device A of a two-device account: B stops ringing within 1 s; A stays connected; server log shows A excluded.

### 1.2 expireRingingCalls caller attribution
- **What:** Ringing-timeout job must record the original caller ID, callee ID, and reason `no_answer` on the call record and emit `call.missed` to the callee and `call.ended{reason:no_answer}` to the caller.
- **Why:** Missed-call history currently shows wrong or empty caller.
- **Acceptance:** Let a call ring out: callee sees 'Missed call from <caller>'; caller sees 'No answer'; DB row has caller_id populated.

### 1.3 endCall fan-out to all participants and devices
- **What:** `endCall` must notify every participant and every installation, including those still ringing, and be idempotent.
- **Why:** Ghost ringing and stuck 'in call' UI.
- **Acceptance:** Caller hangs up while callee rings on 3 devices: all 3 stop within 1 s; repeated endCall returns 200 with no duplicate events.

### 1.4 Call state machine and idempotency keys
- **What:** Server-authoritative states (ringing, connecting, active, ended) with transition validation and client request IDs.
- **Why:** Race conditions between answer/decline/hangup.
- **Acceptance:** Concurrent answer and decline: exactly one wins; the loser receives a 409 with current state.

### 1.5 VoIP push (PushKit / FCM high priority) with call payload
- **What:** Dedicated call push channel carrying minimal encrypted call metadata.
- **Why:** Calls must ring when the app is killed, on iOS and Android.
- **Acceptance:** Killed app on iPhone and Android rings within 3 s; CallKit/ConnectionService shows caller name.

### 1.6 TURN credentials endpoint
- **What:** Short-lived TURN credentials (TTL 10 min), regionally distributed TURN with TCP/443 and TLS fallbacks.
- **Why:** Calls fail on restrictive networks.
- **Acceptance:** Call connects on a network that blocks UDP; credentials expire after TTL.

### 1.7 Call quality telemetry (privacy-preserving)
- **What:** Opt-in aggregate stats: RTT, packet loss, codec, relay usage; no content or identifiers beyond a random call ID.
- **Why:** Debug poor call quality without surveillance.
- **Acceptance:** Dashboard shows per-region loss percentiles; no user IDs stored.

## 2. Calls: Group, Screen Share, Captions

### 2.1 SFU for group calls
- **What:** Selective forwarding unit with simulcast, end-to-end encrypted media frames (SFrame / insertable streams).
- **Why:** Group calls beyond 4 people need an SFU; Signal-class requires E2EE through it.
- **Acceptance:** 8-person call stable; SFU cannot decrypt media (verified by packet capture showing encrypted payloads).

### 2.2 Screen share track with system audio
- **What:** SFU support for an additional screen track plus optional audio track, with layer switching.
- **Why:** Requested in-call feature; audio is often missing.
- **Acceptance:** iOS (ReplayKit) and Android (MediaProjection) share screen with audio; viewers hear audio in sync within 200 ms.

### 2.3 Live captions relay
- **What:** Optional captions produced on-device and relayed as encrypted data-channel messages; server never sees plaintext.
- **Why:** Accessibility (owner is blind; captions help Deaf users).
- **Acceptance:** Captions appear on remote devices within 1.5 s; server logs contain only ciphertext sizes.

### 2.4 Raise hand, reactions, mute-all requests
- **What:** Data-channel event types with server validation of moderator role.
- **Why:** Parity with modern call apps.
- **Acceptance:** Reaction appears for all participants; non-moderator mute-all request rejected.

### 2.5 Call links
- **What:** Create/revoke shareable call links with admin approval option.
- **Why:** Signal has call links.
- **Acceptance:** Link joins call; revoked link returns 410.

### 2.6 Accessible call event announcements
- **What:** Server emits structured events (joined, left, muted, screen sharing started) so clients can announce via VoiceOver/TalkBack.
- **Why:** Blind users need audible context.
- **Acceptance:** Each event has a localized human-readable string key.

## 3. Profiles and Avatars

### 3.1 Public avatars PUT/PATCH
- **What:** `PUT /v1/profile/avatar` (replace) and `PATCH /v1/profile` (partial fields) with size and MIME validation, returning a versioned URL.
- **Why:** Profile pictures not updating across devices.
- **Acceptance:** Upload JPEG/PNG/HEIC up to 5 MB; other devices and contacts see new avatar within 5 s; old version invalidated in CDN.

### 3.2 Encrypted profiles option
- **What:** Profile name/avatar encrypted with a profile key shared only with contacts.
- **Why:** Signal-class privacy.
- **Acceptance:** Server stores ciphertext only; non-contacts cannot decrypt.

### 3.3 Profile change push
- **What:** Silent push/WebSocket event `profile.updated` with version number.
- **Why:** Avoid stale names and avatars.
- **Acceptance:** Contact list refreshes without app restart.

## 4. Auto-Translate

### 4.1 Diagnose why client translate fails
- **What:** Audit current flow: missing API key on server, CORS/ATS, wrong endpoint, no error surfacing. Return structured errors.
- **Why:** Auto-translate is reported not working.
- **Acceptance:** Server returns `{error_code, message}`; client shows readable failure; root cause documented.

### 4.2 Reliable translate API
- **What:** `POST /v1/translate` with provider abstraction (e.g., Google, DeepL, or self-hosted), retries, timeouts, batching.
- **Why:** Single point of failure today.
- **Acceptance:** p95 < 800 ms; provider outage falls back to secondary; 99.5% success in load test.

### 4.3 Language detection endpoint
- **What:** `POST /v1/detect-language` or included in translate response.
- **Why:** Avoid translating text already in the user's language.
- **Acceptance:** Detects top 30 languages with >95% accuracy on test set.

### 4.4 Per-chat translate toggle sync
- **What:** Store per-conversation setting (on/off, target language) and sync across devices.
- **Why:** Settings currently per-device or lost.
- **Acceptance:** Toggle on iPhone reflects on Android within 5 s.

### 4.5 Privacy disclosure and on-device option
- **What:** Clear note that server translation sees plaintext; support on-device translation where available (Apple Translation framework, ML Kit).
- **Why:** E2EE conflict.
- **Acceptance:** Settings explain trade-off; on-device mode sends nothing to server.

### 4.6 Translate voice messages
- **What:** Transcribe then translate (opt-in).
- **Why:** Accessibility and cross-language use.
- **Acceptance:** Voice note shows transcript and translation.

## 5. Voice Messages and Attachments

### 5.1 Reliable blob URLs
- **What:** Attachment upload returns a stable ID and a signed download URL; never return localhost or internal hostnames.
- **Why:** Voice messages from Android don't play on iPhone.
- **Acceptance:** Android-recorded note plays on iPhone and vice versa, 20/20 attempts.

### 5.2 Bearer auth on attachment download
- **What:** Accept `Authorization: Bearer` (or signed URL) consistently for all attachment GETs.
- **Why:** iOS AVPlayer requests drop cookies/headers.
- **Acceptance:** Download succeeds with Bearer token; unauthenticated request returns 401.

### 5.3 Relative path resolution
- **What:** Server always returns absolute HTTPS URLs; if relative paths exist, document the base URL.
- **Why:** Clients mis-resolve relative paths.
- **Acceptance:** No relative URLs in any API response (contract test).

### 5.4 Correct MIME types and transcoding
- **What:** Store and serve correct `Content-Type` (audio/mp4 AAC, audio/ogg Opus); optional server transcode to AAC for iOS compatibility, or require clients to record AAC/M4A.
- **Why:** iOS cannot play Ogg/Opus natively in AVPlayer.
- **Acceptance:** Every voice note served with playable MIME on both platforms; HTTP Range requests supported (206).

### 5.5 Waveform and duration metadata
- **What:** Accept and return duration and waveform in attachment metadata.
- **Why:** Accessible playback ('Voice message, 12 seconds').
- **Acceptance:** Metadata present on all voice notes.

### 5.6 Resumable uploads
- **What:** tus or chunked uploads with resume.
- **Why:** Poor networks.
- **Acceptance:** Upload resumes after network drop at 50%.

### 5.7 Attachment encryption
- **What:** Client-side encrypted attachments with key in message; server stores ciphertext.
- **Why:** Signal-class.
- **Acceptance:** Server-side file is not decodable without message key.

## 6. End-to-End Encryption

### 6.1 Group E2EE frames
- **What:** Server routes opaque group message envelopes; never parses content.
- **Why:** Group messages must be E2EE.
- **Acceptance:** Server DB/logs contain no group plaintext.

### 6.2 Sender keys
- **What:** Sender key distribution messages and per-group membership-change rekey.
- **Why:** Efficient group encryption.
- **Acceptance:** Removed member cannot decrypt messages sent after removal.

### 6.3 Prekey service
- **What:** Signed prekeys, one-time prekeys, refill alerts, Kyber/PQ prekeys (PQXDH).
- **Why:** Signal protocol foundation; post-quantum readiness.
- **Acceptance:** Server warns client when one-time prekeys < 10; PQ prekey present in bundle.

### 6.4 Multi-device linking
- **What:** Secure device linking via QR with per-device identity and message fan-out.
- **Why:** Parity with Signal linked devices.
- **Acceptance:** Linked device receives new messages; unlinking revokes immediately.

### 6.5 Encrypted backup support
- **What:** Store encrypted backups keyed by user-held recovery key.
- **Why:** Restore without server reading data.
- **Acceptance:** Restore on new phone with key; server cannot decrypt.

## 7. Disappearing Messages and View-Once

### 7.1 Server-enforced disappearing timers
- **What:** Server deletes stored envelopes and attachments after timer expiry even if undelivered.
- **Why:** Client-only enforcement is insufficient.
- **Acceptance:** Undelivered message with 1 h timer is purged from DB and storage after 1 h.

### 7.2 Timer sync events
- **What:** Timer changes are sent as system messages to all members and devices.
- **Why:** Consistency.
- **Acceptance:** Change on one device reflects everywhere.

### 7.3 View-once delete
- **What:** Attachment deleted from storage after first successful download by each recipient device.
- **Why:** View-once must actually be once.
- **Acceptance:** Second download returns 410 Gone.

### 7.4 Default timer for new chats
- **What:** Account-level setting synced.
- **Why:** Signal feature.
- **Acceptance:** New chats inherit default.

## 8. Sealed Sender and Metadata Minimization

### 8.1 Sealed sender delivery
- **What:** Sender certificate plus unidentified delivery access keys; server cannot see sender for 1:1 messages.
- **Why:** Signal's core metadata protection.
- **Acceptance:** Delivery logs do not contain sender ID for sealed messages.

### 8.2 Log minimization
- **What:** No IP retention beyond 24 h; no message timestamps beyond operational need.
- **Why:** Reduce data exposure.
- **Acceptance:** Log retention policy documented and enforced by job.

### 8.3 Contact discovery privacy
- **What:** Hashed or enclave-based contact discovery; rate limited.
- **Why:** Avoid uploading address books in plaintext.
- **Acceptance:** Server cannot reconstruct address book from stored data.

### 8.4 Transparency report readiness
- **What:** Document what data exists to answer legal requests.
- **Why:** Trust.
- **Acceptance:** Published data inventory.

## 9. Safety Numbers and Identity

### 9.1 Identity key change push alerts
- **What:** When a contact's identity key changes, notify all their contacts' devices with a system event.
- **Why:** Detect possible MITM or reinstall.
- **Acceptance:** Contact reinstalls: chat shows 'safety number changed' within 5 s.

### 9.2 Safety number verification state sync
- **What:** Sync 'verified' flag across own devices.
- **Why:** Consistency.
- **Acceptance:** Verify on iPhone shows verified on Android.

### 9.3 Key transparency (future)
- **What:** Append-only log of identity keys.
- **Why:** Signal-class roadmap.
- **Acceptance:** Design doc approved.

## 10. Push Notifications

### 10.1 E2EE push payloads
- **What:** Push contains only an encrypted blob or 'new message' wake signal; client decrypts in Notification Service Extension (iOS) / FCM handler (Android).
- **Why:** Apple/Google must not see content.
- **Acceptance:** Push payload inspection shows no plaintext.

### 10.2 Deep links
- **What:** Payload includes encrypted conversation ID to open the right chat or call.
- **Why:** Tapping a notification should open the right place.
- **Acceptance:** Tap opens exact conversation 10/10.

### 10.3 Rich notification privacy levels
- **What:** Setting: name and message / name only / no name or content; synced.
- **Why:** Signal parity.
- **Acceptance:** Each level verified on lock screen.

### 10.4 Notification badge counts
- **What:** Server-tracked unread counts per device.
- **Why:** Accurate badges.
- **Acceptance:** Badge matches unread count after reading on another device.

### 10.5 Push token hygiene
- **What:** Remove invalid tokens on APNs/FCM feedback.
- **Why:** Delivery reliability.
- **Acceptance:** Invalid tokens purged within 1 h.

## 11. Receipts, Typing, Presence

### 11.1 Read receipts toggle
- **What:** Reciprocal setting enforced server-side.
- **Why:** Privacy control.
- **Acceptance:** With receipts off, neither side sees read status.

### 11.2 Typing indicators toggle
- **What:** Same model as receipts.
- **Why:** Privacy.
- **Acceptance:** Off means no typing events sent or relayed.

### 11.3 Presence / last seen controls
- **What:** Everyone / contacts / nobody.
- **Why:** Privacy.
- **Acceptance:** Server withholds presence according to setting.

### 11.4 Delivery receipts
- **What:** Per-device delivery tracking.
- **Why:** Reliability feedback.
- **Acceptance:** Double-check appears when any recipient device receives.

## 12. Link Previews

### 12.1 Link preview fetch proxy
- **What:** Server-side proxy that fetches Open Graph data without revealing the user's IP, with size limits, SSRF protection (block private IPs), and timeouts.
- **Why:** Safe, private previews.
- **Acceptance:** Preview works for top sites; requests to 10.x/169.254.x blocked.

### 12.2 Preview disable setting
- **What:** Synced toggle.
- **Why:** Privacy.
- **Acceptance:** Off means no fetch occurs.

## 13. Stories / Status (Optional)

### 13.1 Stories storage with 24 h expiry
- **What:** Encrypted story posts, audience lists, auto-delete.
- **Why:** Signal has stories.
- **Acceptance:** Story deleted at 24 h from storage.

### 13.2 Viewer list and replies
- **What:** Encrypted view receipts and replies routed to DM.
- **Why:** Engagement.
- **Acceptance:** Poster sees viewers; replies arrive in chat.

### 13.3 Global disable
- **What:** Account setting to turn stories off.
- **Why:** Some users don't want them.
- **Acceptance:** Off hides stories feature for that user.

## 14. Usernames and Discovery

### 14.1 Username search rate limits
- **What:** Per-account and per-IP limits with exponential backoff.
- **Why:** Prevent enumeration.
- **Acceptance:** More than 30 lookups/min returns 429.

### 14.2 Username links and QR
- **What:** Revocable username links.
- **Why:** Share without phone number.
- **Acceptance:** Revoked link no longer resolves.

### 14.3 Phone number privacy
- **What:** Hide phone number from everyone option.
- **Why:** Signal parity.
- **Acceptance:** Contacts cannot see number when hidden.

## 15. Safety: Report, Block, Spam

### 15.1 Block sync
- **What:** Block list synced across devices; server drops messages and calls from blocked users.
- **Why:** Reliability.
- **Acceptance:** Blocked user's call never rings any device.

### 15.2 Report spam
- **What:** Report endpoint accepting user-forwarded message content (consensual) plus sender ID.
- **Why:** Abuse handling under E2EE.
- **Acceptance:** Report stored; reporter receives acknowledgement.

### 15.3 Message requests
- **What:** Unknown senders land in requests; accept/decline/block.
- **Why:** Spam reduction.
- **Acceptance:** Unknown sender cannot see read receipts until accepted.

### 15.4 Abuse rate limits
- **What:** Limits on new-chat creation and group invites.
- **Why:** Spam waves.
- **Acceptance:** Burst of 100 new chats in 1 min throttled.

## 16. Storage and CDN

### 16.1 R2 / CDN signed URL TTL
- **What:** Signed URLs with short TTL (e.g., 15 min) and refresh endpoint.
- **Why:** Leaked URLs should expire.
- **Acceptance:** URL returns 403 after TTL; refresh issues new URL.

### 16.2 Range and caching headers
- **What:** Support HTTP Range, ETag, correct Cache-Control.
- **Why:** Streaming audio/video.
- **Acceptance:** Seek in voice note works on iOS.

### 16.3 Orphan cleanup
- **What:** Delete unreferenced attachments after 30 days.
- **Why:** Cost and privacy.
- **Acceptance:** Orphan job metrics show deletions.

## 17. Censorship Resistance

### 17.1 Proxy support server hints
- **What:** Publish proxy configuration format (like Signal TLS proxy) and server endpoint discovery.
- **Why:** Users in restricted countries.
- **Acceptance:** App connects through a documented proxy.

### 17.2 Domain fronting / alternate endpoints
- **What:** Multiple ingress domains.
- **Why:** Resilience.
- **Acceptance:** Fallback endpoint used when primary blocked.

## 18. Reliability and Operations

### 18.1 WebSocket reconnection and message queue
- **What:** Ordered, durable per-device queues with acknowledgements.
- **Why:** No lost messages.
- **Acceptance:** Kill network for 10 min: all messages arrive in order after reconnect.

### 18.2 API versioning and contract tests
- **What:** OpenAPI spec shared with iOS and Android.
- **Why:** Avoid client breaks.
- **Acceptance:** CI fails on breaking change.

### 18.3 Status page and error codes
- **What:** Public status page; consistent error schema.
- **Why:** Trust and debugging.
- **Acceptance:** Status page live.

### 18.4 Load and chaos testing
- **What:** Regular load tests to target concurrency.
- **Why:** Scale.
- **Acceptance:** Report with p95 latencies.

## 19. Accessibility-First Server Features

### 19.1 Accessible strings for system events
- **What:** Every system event carries a localization key and parameters for screen readers.
- **Why:** Owner is blind; VoiceOver/TalkBack must announce clearly.
- **Acceptance:** All system events have keys; audit passes.

### 19.2 Voice message transcription (opt-in, on-device preferred)
- **What:** Server endpoint only as fallback with disclosure.
- **Why:** Accessibility.
- **Acceptance:** Transcript available for voice notes.

### 19.3 Image descriptions
- **What:** Alt-text field on image attachments, plus optional AI description (opt-in).
- **Why:** Blind users need image context.
- **Acceptance:** Alt text sent and read aloud.

## 20. Imaginative / Beyond Signal

### 20.1 Scheduled messages
- **What:** Server holds encrypted message until send time.
- **Why:** Convenience.
- **Acceptance:** Message delivered within 1 min of scheduled time.

### 20.2 Edit and delete-for-everyone with time window
- **What:** Encrypted edit events.
- **Why:** Parity with modern apps.
- **Acceptance:** Edits visible on all devices; history marked edited.

### 20.3 Polls and reactions
- **What:** Encrypted poll messages.
- **Why:** Groups.
- **Acceptance:** Votes tallied client-side; server sees ciphertext.

### 20.4 Communities / channels
- **What:** Large broadcast groups with admin roles.
- **Why:** Growth.
- **Acceptance:** 10k-member channel delivers within 30 s.

### 20.5 Emergency SOS share
- **What:** Live location share to chosen contacts, auto-expiring.
- **Why:** Safety.
- **Acceptance:** Location stops after expiry.

### 20.6 Panic wipe remote signal
- **What:** User-initiated remote wipe of a lost linked device.
- **Why:** Security.
- **Acceptance:** Lost device unlinks and wipes on next connect.

### 20.7 Hearing/vision mode profile sync
- **What:** Sync accessibility preferences across devices.
- **Why:** Accessibility.
- **Acceptance:** Preferences apply on new device.

### 20.8 Payments (future, regulated)
- **What:** Research only.
- **Why:** Signal has MobileCoin; evaluate.
- **Acceptance:** Decision memo.

## Suggested Priority

1. Voice attachments (Section 5) and call signaling (Section 1): user-visible bugs today.
2. Auto-translate fixes (Section 4) and avatars (Section 3).
3. Push, E2EE, disappearing messages, sealed sender (Sections 6 to 11).
4. Everything else as roadmap.
