# Dual RTC: LiveKit + Agora

Admin `CALL_RTC_PROVIDER` is `livekit` (default) or `agora`. Each call keeps its provider; create/join/accept responses include the grant for that provider.

## Response fields (Sites `mintCallRtcToken`)

| Field | LiveKit | Agora |
|-------|---------|-------|
| `provider` | `"livekit"` | `"agora"` |
| `livekit` | `{ token, identity?, room, expires_at?, url? }` | `null` |
| `livekit_url` | wss URL | `null` |
| `agora` | `null` | `{ token, app_id, channel, uid, expires_at, … }` |
| `token` | LiveKit JWT | Agora AccessToken2 |
| `app_id` | `null` | Agora App ID |
| `channel` | room name | Agora channel (= room) |
| `uid` | profile id string | numeric uid (string or number) |

Clients also accept flat `agora_app_id` / `agora_token` and legacy flat LiveKit `{ token, livekit_url }`.

**Never** ship `AGORA_APP_CERTIFICATE` or Customer Secret in the app. Prefer `appId + token + channel + uid` from the server.

## Client behavior

- `provider=livekit` (or LiveKit grant only) → existing LiveKit path (unchanged), including frame E2EE / `call_key`.
- `provider=agora` (or Agora grant) → Agora RTC SDK join; mic/camera/leave routed through a thin session wrapper.
- CallKit / dial / ringback still run; remote join stops ringback for both providers.
- Agora frame E2EE via `call_key` and Agora video canvas / screen share are **follow-ups** (documented in call encryption label).

## Dependencies

- iOS SPM: `AgoraRtcEngine_iOS` → product `RtcBasic` (≥4.5)
- Android Maven `https://download.agora.io/maven/` → `io.agora.rtc:full-sdk:4.5.2`
