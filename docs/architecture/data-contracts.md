# bcup Data Contracts (Firestore)

This document freezes Firestore field-level contracts for V1.

## Contract conventions

- **Type** uses Firestore-friendly types: `string`, `number`, `boolean`, `timestamp`, `array<T>`, `map<K,V>`, `object`.
- **Required** means the field must exist on document create.
- **Nullable** means explicit `null` is allowed.
- **Default** applies if omitted on create.
- **Set by** indicates source of truth (`client`, `server`, or `either`).
- **Immutable** means value cannot change after create.

## Global rules

- `createdAt`: required, non-null, set by server timestamp on create, immutable.
- `updatedAt`: required, non-null, set by server timestamp on create and every update.
- Document IDs are immutable.
- Reject unknown fields unless explicitly approved in this contract.

## Identity decision

- **Decision:** `profileId == auth.uid` for V1.
- Membership document ID format is `{communityId}_{profileId}`.

---

## `profiles/{profileId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `profileId`. |
| `googleAuthId` | string | yes | no | none | server | yes | Google/Firebase auth identity key. |
| `displayName` | string | yes | no | `""` | client | no | Can be required in onboarding UX before completion. |
| `profilePhotoUrl` | string | no | yes | `null` | client | no | Firebase Storage URL expected. |
| `overallOdds` | number | yes | no | `0` | server | no | Derived field from game outcomes. |
| `ageConfirmed21PlusAt` | timestamp | no | yes | `null` | client | no | Set on one-time age confirmation step. |
| `onboardingCompleteAt` | timestamp | no | yes | `null` | client | no | Set when required onboarding fields are complete. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "uid_abc123",
  "googleAuthId": "uid_abc123",
  "displayName": "Maya",
  "profilePhotoUrl": null,
  "overallOdds": 0,
  "ageConfirmed21PlusAt": null,
  "onboardingCompleteAt": null,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

---

## `communities/{communityId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `communityId`. |
| `name` | string | yes | no | none | client | no | Non-empty; enforce max length in app/function validation. |
| `createdByProfileId` | string | yes | no | none | server | yes | Profile that created community. |
| `inviteCode` | string | yes | no | none | server | no | Must be unique across communities. |
| `inviteLink` | string | yes | no | none | server | no | Derived from current invite code. |
| `memberCount` | number | yes | no | none | server | no | Current member count; increments on join (max 350). Omitted on legacy docs until backfilled. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "community_001",
  "name": "Friday Pong",
  "createdByProfileId": "uid_abc123",
  "inviteCode": "ABC123",
  "inviteLink": "https://bcup.app/join/ABC123",
  "memberCount": 12,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

---

## `memberships/{membershipId}`

Recommended ID format: `{communityId}_{profileId}` for uniqueness.

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | server | yes | Must equal `membershipId`. |
| `communityId` | string | yes | no | none | server | yes | Must reference existing community. |
| `profileId` | string | yes | no | none | server | yes | Must reference existing profile. |
| `joinedAt` | timestamp | yes | no | server timestamp | server | yes | Set once when membership is created. |
| `communityOdds` | number | no | no | `0` | server | no | Derived field; scoped to community+profile. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "community_001_uid_abc123",
  "communityId": "community_001",
  "profileId": "uid_abc123",
  "joinedAt": "SERVER_TIMESTAMP",
  "communityOdds": 0,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

---

## `gameLogs/{gameLogId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `gameLogId`. |
| `communityId` | string | yes | no | none | client | yes | Community where game occurred. |
| `gameType` | string enum | yes | no | none | client | yes | `PONG \| BEER_BALL \| BATTLE_PONG \| BASEBALL`. |
| `createdByProfileId` | string | yes | no | none | server | yes | Creator/owner of log. |
| `participantProfileIds` | array<string> | yes | no | none | client | no | Must be unique IDs. |
| `winnerProfileIds` | array<string> | yes | no | none | client | no | Min length 1. |
| `loserProfileIds` | array<string> | yes | no | none | client | no | Min length 1. |
| `photoUrls` | array<string> | yes | no | none | client | no | Min length 1. |
| `notes` | string | no | yes | `null` | client | no | Optional free-text note. |
| `pongStats` | object | no | yes | `null` | client | no | Required for `PONG` only if product decides strict mode. |
| `pongStats.playerCupsHit` | map<string, number> | no | yes | `null` | client | no | Map of profileId to integer cups hit. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "gameLog_001",
  "communityId": "community_001",
  "gameType": "PONG",
  "createdByProfileId": "uid_abc123",
  "participantProfileIds": ["uid_abc123", "uid_def456"],
  "winnerProfileIds": ["uid_abc123"],
  "loserProfileIds": ["uid_def456"],
  "photoUrls": ["https://storage.googleapis.com/bcup/logs/gameLog_001/photo1.jpg"],
  "notes": "Close game.",
  "pongStats": {
    "playerCupsHit": {
      "uid_abc123": 8,
      "uid_def456": 5
    }
  },
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### `gameLogs` invariants

- `winnerProfileIds.length >= 1`
- `loserProfileIds.length >= 1`
- `photoUrls.length >= 1`
- `winnerProfileIds` is a subset of `participantProfileIds`
- `loserProfileIds` is a subset of `participantProfileIds`
- No overlap between winners and losers
- No duplicates in `participantProfileIds`, `winnerProfileIds`, or `loserProfileIds`

---

## `brackets/{bracketId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `bracketId`. |
| `communityId` | string | yes | no | none | client | yes | Scope for participants and odds. |
| `participantProfileIds` | array<string> | yes | no | none | server | no | Auto-populate from current members at creation. |
| `seedMethod` | string enum | yes | no | none | client | yes | `COMMUNITY_ODDS \| MANUAL \| RANDOM`. |
| `status` | string enum | yes | no | `DRAFT` | client | no | `DRAFT \| ACTIVE \| COMPLETE`. |
| `rounds` | array<object> | yes | no | `[]` | server | no | Structured round/match data. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "bracket_001",
  "communityId": "community_001",
  "participantProfileIds": ["uid_abc123", "uid_def456", "uid_ghi789", "uid_jkl012"],
  "seedMethod": "COMMUNITY_ODDS",
  "status": "DRAFT",
  "rounds": [],
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### Bracket `rounds` — match objects (2v2-friendly)

Each element of `rounds` is product-defined; typically a **round** contains **matches**. For each **match**, align with `gameLogs` where outcomes are attributed:

| Field (per match) | Type | Notes |
|---|---|---|
| `matchId` | string | Stable id within the bracket. |
| `participantProfileIds` | array<string> | Everyone in the match (e.g. four ids for 2v2). |
| `winnerProfileIds` | array<string> | Min length 1; e.g. two ids for a winning team. |
| `loserProfileIds` | array<string> | Min length 1; e.g. two ids for a losing team. |

**Invariants (same as `gameLogs`):** `winnerProfileIds` and `loserProfileIds` are subsets of `participantProfileIds`; sets are disjoint; no duplicate ids within each array.

Firestore security rules only enforce **top-level** bracket keys (`hasBracketKeys`); **nested** match validation should be enforced in **Cloud Functions** (or the client) when implementing `updateMatchResult`.

---

## Derived fields ownership

- `profiles.overallOdds`: computed by Cloud Functions on game log create/update/delete.
- `memberships.communityOdds`: computed by Cloud Functions on game log create/update/delete.

Clients should treat derived fields as read-only.

## Query/index checklist (minimum)

- `memberships`: `profileId ASC, joinedAt DESC`
- `memberships`: `communityId ASC, joinedAt ASC`
- `gameLogs`: `communityId ASC, createdAt DESC`
- `gameLogs`: `createdByProfileId ASC, createdAt DESC`
- `brackets`: `communityId ASC, createdAt DESC`
- `communities`: `inviteCode ASC` (lookup by invite code)

## Change control

- **Breaking change policy:** schema changes require updating this doc and adding a migration note in the PR.
- Any schema change must update this file before implementation.
- If a field is renamed/removed, include a migration note in PR description.
