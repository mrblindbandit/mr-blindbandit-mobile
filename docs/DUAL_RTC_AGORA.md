# Dual RTC: LiveKit + Agora

Admin `CALL_RTC_PROVIDER` is `livekit` (default) or `agora`. Each call keeps its provider; create/join/accept responses include the grant for that provider.

## Response fields (Sites `mintCallRtcToken`)

| Field | LiveKit | Agora |
|-------|---------|-------|
| `rtc_provider` | `"livekit"` | `"agora"` |
| `livekit` | `{ token, identity?, room, expires_at?, url? }` | `null` |
| `livekit_url` | wss URL | `null` |
| `rtc` | LiveKit grant object | `{ provider, app_id, channel, user_account, token, url: null }` |
| `token` | LiveKit JWT | Agora AccessToken2 from `buildTokenWithUserAccount` |
| `user_account` | absent | profile id string (the token subject) |

Production Agora mint does **not** send a numeric `uid` or a nested `agora` object. The token is an Agora user-account token. Clients must `joinChannelWithUserAccount` (Android) / `joinChannelByUserAccount` (iOS) with `user_account`. A numeric `uid` grant is still accepted when present.

`preferred_provider=agora` does not switch a call by itself. `client_opt_in_required` is true: the client sends `rtc_provider=agora` on create. The call row is then locked to that provider.

Clients also accept flat `agora_app_id` / `agora_token` and legacy flat LiveKit `{ token, livekit_url }`.

**Never** ship `AGORA_APP_CERTIFICATE` or Customer Secret in the app. Prefer `appId + token + channel + uid` from the server.

## Client behavior

- `provider=livekit` (or LiveKit grant only) → existing LiveKit path (unchanged), including frame E2EE / `call_key`.
- `provider=agora` (or Agora grant) → Agora RTC SDK join; mic/camera/leave routed through a thin session wrapper.
- CallKit / dial / ringback still run; remote join stops ringback for both providers.
- Agora frame E2EE via `call_key` and Agora video canvas / screen share are **follow-ups** (documented in call encryption label).

## Agora call audio (2.3.0)

Both clients apply this before join. The profile only produces stereo when the SDK is on media volume, which is the game-streaming scenario.

| Setting | Value |
| --- | --- |
| Profile | `AUDIO_PROFILE_MUSIC_HIGH_QUALITY_STEREO` (48 kHz, stereo, up to 128 kbps) |
| Scenario | `AUDIO_SCENARIO_GAME_STREAMING` (media volume, not the telephony volume) |
| Capture | `setAdvancedAudioOptions` with `audioProcessingChannels = 2` |
| AI noise suppression | `setAINSMode(false)` |
| Traditional ANS | `che.audio.ans.enable = false` |
| Echo cancellation | stays on (`che.audio.aec.enable = true`) |
| AGC | on, at unity playback/recording gain (100), so quiet speech is lifted without a boost |
| Spatial | `ILocalSpatialAudioEngine` / `AgoraLocalSpatialAudioKit`: self at the origin, remotes on a circle, `removeRemotePosition` when someone leaves |
| Doppler | off |
| Air absorption | on, attenuation 0.08, about 1.6 m away so speech stays clear |
| Headphone EQ | over-ear for wired, in-ear for Bluetooth, off for speaker and earpiece |

Speaker, earpiece, wired headphones, and Bluetooth still route through Agora (`setEnableSpeakerphone` / `onAudioRouteChanged`). The Android path does not force `MODE_IN_COMMUNICATION` during an Agora call, and iOS does not force `AVAudioSession.Mode.voiceChat` for Agora, because both of those turn the call back onto telephony processing and Apple or Android noise suppression. LiveKit calls keep the previous voice-chat session.

VoiceOver / TalkBack hears the seat ("Emma joined, on your left.") and a route change onto headphones. A 1:1 seat is in front. A group stays up for two minutes after the last remote leaves, matching the LiveKit rule. A 1:1 still ends when the other person leaves.

## Dependencies

- iOS SPM: `AgoraRtcEngine_iOS` → product `RtcBasic` (≥4.5)
- Android Maven `https://download.agora.io/maven/` → `io.agora.rtc:full-sdk:4.5.2`
