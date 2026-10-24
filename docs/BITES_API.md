# Blind Bandit Bites — iOS client contract

Native SwiftUI Bites tab + profiles wire to the live Blindbandit social API.

## Feed

| Client action | Endpoint | Notes |
|---|---|---|
| Home feed (text) | `GET /v1/social/newsfeed?limit&offset` | Primary Bites tab content today |
| Alt feed | `GET /v1/social/feed` | Same shape as newsfeed |
| Short-video BanditBites | `GET /v1/social/bites` | Requires `video_url` on publish; empty in seed |
| Publish text Bite | `POST /v1/social/posts` | Body `{ "body", "media"? }` |
| Publish video Bite | `POST /v1/social/bites` | Requires `video_url` |
| Like / unlike | `POST\|DELETE /v1/social/posts/{id}/like` | Empty JSON body on POST |
| React | `POST /v1/social/posts/{id}/react` | `{ "reaction": "like"\|… }` |
| Comments | `GET\|POST /v1/social/posts/{id}/comments` | `{ "body" }` on POST |
| Delete own | `DELETE /v1/social/posts/{id}` | |
| Report | `POST /v1/social/reports` | `target_type`: use `"post"` for Bites until `"bite"` exists |

Envelope: `{ "success", "data": { "items": [...] } }`. Timestamps are **ms** epoch.

## Profiles / follow

| Action | Endpoint |
|---|---|
| Full profile | `GET /v1/social/profiles/{handle}/full` |
| Follow | `POST /v1/social/profiles/{handle}/follow` body `{}` |
| Unfollow | `DELETE /v1/social/profiles/{handle}/follow` |
| Followers / following | `GET …/followers` · `GET …/following` |
| Profile posts | `GET …/posts` |
| Profile video bites | `GET …/bites` |

Full profile fields used by iOS: `handle`, `display_name`, `bio`, `avatar_url`, `verified`, `followers`, `following`, `posts`, `bites`, `is_following`.

iOS caches newsfeed + profile JSON under Caches/`bites/` for instant open (no spinner when warm).

## Admin (owner only)

Visible in Profile → Admin when `AdminGate` matches `@kheck` / `profile_mr_blindbandit` or server role `owner`/`admin`.

| Action | Endpoint |
|---|---|
| Stats | `GET /v1/social/admin/overview` |
| Reports | `GET /v1/social/admin/reports` |
| Resolve report | `POST /v1/social/admin/reports/{id}/resolve` |
| **Verify** | `POST /v1/social/admin/users/{id}/verify` body `{}` |
| **Unverify** | `POST /v1/social/admin/users/{id}/unverify` body `{}` |
| Ban / reinstate | `POST …/ban` · `POST …/reinstate` |
| Hide / delete Bite | `POST …/posts/{id}/hide` · `DELETE …/posts/{id}` |

Verify persists on the server; the same `VerifiedBadge` (checkmark.seal.fill) appears on profile, Bites authors, chats, and people rows when `verified == true`.

## Tyrese wishlist (gaps)

1. Add `target_type: "bite"` on reports (client uses `"post"` today).
2. Text-only BanditBites publish without mandatory `video_url` (or keep posts as text Bites).
3. Relative `avatar_url` (`/assets/…`) should ideally be absolute HTTPS for Nuke/AsyncImage.
4. Return `role` on `/v1/social/me` so AdminGate does not need hardcoded owner handles.
5. Prefetch counts endpoint batch (`followers/following/bites` for N handles) for people search speed.


## Upcoming batch ea112272-99f2-4d9b-a9a6-8b67922c2cb9 (deploy_authorized)

Deferred until test/build. Planned aliases (not live yet — HTTP 404 as of 2026-10-25):

| Alias | Maps from (live today) |
|---|---|
| `GET /api/v1/feed` | `/v1/social/newsfeed` / `/v1/social/feed` |
| `GET /api/v1/bites` | `/v1/social/bites` |
| `GET /api/v1/users/{handle}` | `/v1/social/profiles/{handle}/full` |
| `/api/v1/admin/…` verify | `/v1/social/admin/users/{id}/verify` |

iOS `BitesAPI.requestSocial` falls through to `/api/v1/feed` and `/api/v1/bites` on primary 404 so the client picks up the batch without another app release once deployed.
