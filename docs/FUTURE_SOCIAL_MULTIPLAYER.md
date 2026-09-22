# Future Social and Multiplayer Foundation

## Status

This is a schema and interface plan only. Do not expose friends, QR invites, visits, multiplayer, public profiles, global child search, or open child text chat in production UI. No realtime multiplayer implementation is included in this sprint.

## Safety model

Friendship is a relationship between child profiles authorized by both parent accounts. Children cannot search for people or accept invitations. Profiles are private and disclose only an approved in-game nickname/avatar to an accepted friend. There is no free-form child chat; future communication is limited to curated emotes, safe preset phrases, and game actions.

## Schema-only foundation

```sql
friend_invites(
  id TEXT PRIMARY KEY,
  created_by_account_id TEXT NOT NULL REFERENCES accounts(id),
  child_profile_id TEXT NOT NULL REFERENCES child_profiles(id),
  invite_token_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL CHECK(status IN ('pending','accepted','expired','revoked')),
  expires_at INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)

friendships(
  id TEXT PRIMARY KEY,
  child_profile_a_id TEXT NOT NULL REFERENCES child_profiles(id),
  child_profile_b_id TEXT NOT NULL REFERENCES child_profiles(id),
  approved_by_account_a_id TEXT NOT NULL REFERENCES accounts(id),
  approved_by_account_b_id TEXT NOT NULL REFERENCES accounts(id),
  status TEXT NOT NULL CHECK(status IN ('active','blocked','ended')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  CHECK(child_profile_a_id <> child_profile_b_id),
  UNIQUE(child_profile_a_id, child_profile_b_id)
)

house_visits(
  id TEXT PRIMARY KEY,
  host_child_profile_id TEXT NOT NULL REFERENCES child_profiles(id),
  guest_child_profile_id TEXT NOT NULL REFERENCES child_profiles(id),
  friendship_id TEXT NOT NULL REFERENCES friendships(id),
  status TEXT NOT NULL CHECK(status IN ('planned','active','completed','cancelled')),
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)

multiplayer_sessions(
  id TEXT PRIMARY KEY,
  durable_object_key TEXT NOT NULL UNIQUE,
  activity TEXT NOT NULL CHECK(activity IN ('house_visit','co_op_minigame','dress_up','cooking','tidy_up','dance','classroom')),
  status TEXT NOT NULL CHECK(status IN ('forming','active','ended')),
  created_at INTEGER NOT NULL,
  ended_at INTEGER
)

session_members(
  session_id TEXT NOT NULL REFERENCES multiplayer_sessions(id),
  child_profile_id TEXT NOT NULL REFERENCES child_profiles(id),
  parent_account_id TEXT NOT NULL REFERENCES accounts(id),
  role TEXT NOT NULL CHECK(role IN ('host','guest')),
  joined_at INTEGER NOT NULL,
  left_at INTEGER,
  PRIMARY KEY(session_id, child_profile_id)
)
```

Migration `0007_guest_identity.sql` creates these tables and the friendship-pair index. Before routes are enabled, add indexes for invite expiry/status, each child side of active friendships, visit participants/status, and open sessions. Route logic must canonicalize the friendship pair because the current unique index only prevents duplicates in the same ordering. Deletion/blocking must revoke outstanding invites, end active visits, and prevent new session tokens.

## Parent-approved QR invite

1. In Parent Area, authenticated Parent A selects one owned child and creates a short-lived, single-use invite.
2. The backend stores only a hash of a high-entropy invite secret. The QR contains a universal/deep link with the opaque secret, not child/account IDs, names, or contact data.
3. Parent B scans it into Parent Area, signs in, sees a minimal parent-facing confirmation (approved avatar/nickname only), and selects one owned child.
4. The backend verifies expiry, ownership, block state, and single use. Parent B approves.
5. Parent A receives a final parent confirmation if policy requires two-step approval; only after both approvals is the canonical child pair inserted into `friendships`.
6. Either parent can revoke/block. Revocation immediately prevents future visits; block additionally suppresses new invites between those accounts without revealing the reason to children.

Invite endpoints should be parent-bearer-only, rate-limited, CSRF/deep-link safe, and idempotent. Screenshots of an expired QR confer no access. QR redemption never signs a user in.

## Durable Object session plan

One Cloudflare Durable Object owns each live session. D1 stores authorization and durable metadata; the DO holds ephemeral presence and game state. The API verifies an active friendship/visit plus both required parent approvals, then mints a short-lived session token bound to session, account, child, role, and installation.

The DO accepts only an allowlisted, versioned command vocabulary for house visits, co-op mini-games, dress-up, cooking, tidy-up, dance, and classroom. It validates role, sequence, rate, and object ownership, assigns monotonic sequence numbers, and broadcasts authoritative state snapshots/deltas. Clients never execute arbitrary remote tools, scripts, asset URLs, or text.

Reconnect uses the last acknowledged sequence and a fresh authorization check. Idle/absolute TTLs close sessions. A parent block, child/account deletion, or entitlement/policy change can force closure. Persist only minimal outcomes needed for progress and abuse review; do not persist voice, free text, or a full movement transcript.

## Interface boundary

Future endpoints may cover invite create/redeem/approve/revoke, friendship list/block, visit propose/approve/end, and session token minting. They must remain unmounted or feature-flagged until privacy, moderation, abuse, load, and physical-device reviews pass. Godot should depend on a disabled `SocialService` interface whose production implementation is absent; no child-facing controls are added now.

## Pre-enable verification

- Both parents' ownership and approvals are enforced, including cross-account child-ID attacks.
- Invite replay, guessing, enumeration, expiry, screenshot reuse, and concurrent redemption fail safely.
- Block/delete revokes sessions promptly.
- DO command schema rejects arbitrary payloads and replay/out-of-order abuse.
- No public directory/profile/search or free-form chat endpoint exists.
- Load, reconnect, regional latency, session cleanup, data retention, incident controls, and child-safety review pass before any UI flag is enabled.
