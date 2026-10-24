# Blind Bandit Bites — Social Feed + Follow API Contract (for Tyrese)

Native clients only (SwiftUI iOS + Kotlin/Compose Android). **No WebView / web embed.**
Base: `https://mrblindbandit.net/api/v1` · Auth: `Authorization: Bearer <Clerk session JWT>` · JSON, UTF-8.
Envelope (matches existing Worker 404 shape): success `{"success":true,"data":...}`; error `{"success":false,"error":{"code","message","request_id"}}`.
Timestamps: epoch ms (matches `social_posts.created_at`). IDs: opaque strings.

## 1. What exists today vs greenfield (checked 2026-10-25 ~04:00 PHT)
| Area | Status |
|---|---|
| `social_posts` table (id, author_id, body, visibility, created_at, updated_at, deleted_at) | **Exists** — 5–6 seed rows, all `public`, author `profile_mr_blindbandit` (read via site-control MCP `list_posts`/`social_health`) |
| Feed/uploads/messages/calls tables | Exist (social 6, feed 5, uploads 1, messages 35, calls 47) |
| Clerk auth, web_push, LiveKit, Resend | Configured (delivery not verified) |
| Public HTTP routes `/api/posts`, `/api/feed`, `/api/social/posts`, `/api/v1/posts`, `/v1/status` | **404 — no live feed endpoints** (`/api/v1/*` returns JSON NOT_FOUND, so the v1 router exists) |
| Mobile app "Chronicle" | Read-only RSS of `https://mrblindbandit.net/feed.xml` (App/ChronicleView.swift, Android chronicle/ChronicleScreen.kt). Not a social feed. |
| Only app API call found | `/api/push/test` |
| Likes, comments, follows, blocks, mutes, mentions, media for posts, profile-by-username API | **Greenfield** |

## 2. Data model (additions)
- `social_posts` + `media_ids` (json), `like_count`, `comment_count`, `visibility` ∈ `public|followers`.
- `post_likes(post_id, user_id, created_at)` PK(post_id,user_id)
- `post_comments(id, post_id, author_id, body, created_at, deleted_at)`
- `follows(follower_id, followee_id, created_at)` PK pair
- `blocks(blocker_id, blocked_id)`, `mutes(muter_id, muted_id)`
- `media(id, owner_id, kind image|video, url, width, height, duration_ms, status pending|ready)`

## 3. Objects
```json
Bite {"id":"post_x","author":ProfileLite,"body":"≤500 chars","visibility":"public|followers",
 "media":[Media],"like_count":0,"comment_count":0,"liked_by_me":false,"mentions":["username"],
 "created_at":0,"updated_at":0}
ProfileLite {"id","username","display_name","avatar_url","verified":false}
Profile = ProfileLite + {"bio","followers_count","following_count","bites_count",
 "is_following":false,"follows_me":false,"is_blocked":false,"is_muted":false}
Media {"id","kind":"image|video","url","thumb_url","width","height","duration_ms","alt_text"}
Page {"items":[...],"next_cursor":"opaque|null"}
```
Pagination everywhere: `?limit=1..50 (default 20)&cursor=<next_cursor>`; order newest first, cursor = `(created_at,id)` keyset.

## 4. Endpoints
### Feed / Bites
| Method | Path | Notes |
|---|---|---|
| GET | `/feed?scope=home\|public&limit&cursor` | home = followed + self; public = all public. Excludes blocked/muted authors, deleted rows. Followers-only bites shown only to followers + author. |
| GET | `/bites/{id}` | 404 if deleted, hidden by privacy, or block either way |
| POST | `/bites` | `{"body","visibility","media_ids":[],"client_id"}` (client_id = idempotency) → 201 Bite. Body or media required. Parses `@username` → mentions. |
| DELETE | `/bites/{id}` | author only; soft delete (`deleted_at`) → 204 |
| GET | `/users/{username}/bites` | profile grid, same privacy rules |

### Likes / Comments
| POST | `/bites/{id}/like` | idempotent → `{"like_count","liked_by_me":true}` |
| DELETE | `/bites/{id}/like` | idempotent |
| GET | `/bites/{id}/comments?limit&cursor` | oldest first |
| POST | `/bites/{id}/comments` | `{"body"≤300}` → 201 Comment; mentions parsed |
| DELETE | `/comments/{id}` | comment author or bite author |

### Media upload (two-step)
| POST | `/media/uploads` | `{"kind","mime","bytes"}` → `{"media_id","upload_url","headers","expires_at"}` (presigned R2 PUT). Limits: image ≤10 MB jpeg/png/heic/webp; video ≤100 MB/60 s mp4/mov. |
| PUT | `upload_url` | raw bytes |
| POST | `/media/{id}/complete` | `{"alt_text"}` → Media status `ready` (server makes thumb). Only `ready` media attachable. |

### Profiles & follows
| GET | `/users/{username}` | → Profile with `followers_count`, `following_count`, `bites_count`, relationship flags. Case-insensitive. 404 if blocked by them. |
| GET | `/users/{username}/followers?limit&cursor` | Page<ProfileLite + is_following> |
| GET | `/users/{username}/following?limit&cursor` | same |
| POST | `/users/{username}/follow` | idempotent → `{"is_following":true,"followers_count"}`; 403 if blocked; 400 self |
| DELETE | `/users/{username}/follow` | idempotent unfollow |

### Safety
| POST/DELETE | `/users/{username}/block` | Block removes follows both ways, hides content both ways |
| POST/DELETE | `/users/{username}/mute` | hides their bites from my feed only; they aren't told |
| GET | `/me/blocks`, `/me/mutes` | Page |
| POST | `/reports` | `{"target_type":"bite|comment|user","target_id","reason"}` (ties to existing trust/report records) |

### Push on mention / social events
- Server sends via existing web_push/APNs/FCM path on: mention in bite or comment, like, comment on my bite, new follower.
- Skip if actor blocked/muted by recipient, or bite not visible to recipient.
- Payload: `{"type":"bite_mention|comment_mention|like|comment|follow","bite_id?","comment_id?","actor_username"}` → reuse `PushRoute` deep link `blindbandit://bites/{id}` / `blindbandit://users/{username}`.
- Register device: existing push registration; settings `GET/PATCH /me/notification-prefs` `{mentions,likes,comments,follows: bool}`.

## 5. Errors
`400 VALIDATION`, `401 UNAUTHENTICATED`, `403 FORBIDDEN|BLOCKED`, `404 NOT_FOUND`, `409 CONFLICT`, `413 TOO_LARGE`, `429 RATE_LIMITED` (+`Retry-After`; create 30/h, comment 120/h, follow 200/day).

## 6. Acceptance checks
1. `GET /feed?scope=public` unauthenticated or authed returns the 5 seed bites newest-first with `next_cursor` null at limit 20; limit=2 paginates with no dupes/gaps.
2. POST bite → appears top of author's home feed and `/users/{u}/bites`; retry with same `client_id` returns same id.
3. Followers-only bite: visible to follower & author, 404 to non-follower and in public feed.
4. DELETE by non-author → 403; by author → 204, then GET → 404, gone from feeds, counts drop.
5. Like twice → count 1; unlike twice → 0.
6. Comment create/list/delete; bite author can delete others' comments.
7. Upload: >10 MB image → 413; incomplete media in `media_ids` → 400; ready media renders with alt_text (VoiceOver/TalkBack reads it).
8. `GET /users/{u}` returns counts; follow → followers_count +1, appears in `/followers` of target and `/following` of me; unfollow reverses; follow self → 400.
9. Block A↔B: each 404 on other's profile/bites, follows removed, no push either way. Mute: hidden from my feed only.
10. `@username` in bite → mentioned user gets one push with deep link opening the bite natively; no push if they muted/blocked author or prefs off.
11. All lists respect blocks/mutes/deleted; no PII beyond ProfileLite in lists.
12. Native only: iOS + Android screens (Feed, Composer, Bite detail, Profile, Followers/Following) with full VoiceOver/TalkBack labels; no WebView.
