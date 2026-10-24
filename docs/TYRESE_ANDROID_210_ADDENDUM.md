# Tyrese — Android 2.0.10 server addendum (paste-ready)

Client workarounds ship in Android 2.0.10; server fixes still needed for full parity with iOS 2.0.9+:

1. **Call end push / answered elsewhere**
   - When device A joins with `installation_id`, do **not** send `call_answered_elsewhere` / `call_end` to that same installation (or include `exclude_installation_id`).
   - Client ignores echo for ~8s after join; server exclusion removes the race.

2. **`expireRingingCalls` / missed-call attribution**
   - Ensure `caller_id` (and handle) remain on expired ringing rows so Android missed-call history labels correctly.

3. **`endCall` push fan-out**
   - Confirm all participant installations receive `call_end` (not only the peer who hung up).

4. **Public avatar**
   - Confirm `PUT /v1/social/me/avatar` (raw JPEG) + `PATCH /v1/social/me` `{ "avatar_url": "" }` are live in production. Android already calls both.

5. **Play Console**
   - No app-server change; ops: add GitHub secret `PLAY_SERVICE_ACCOUNT_JSON` (Play Console API service account with Release to testing track) so `release-aab.yml` auto-uploads internal track.
