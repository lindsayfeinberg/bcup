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
| `overallGamesPlayed` | number | yes | no | `0` | server | no | Count of eligible game logs across all communities. Used for tie-breaking in step 2 of odds-based seeding when sparse (T09.5). |
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
  "overallGamesPlayed": 0,
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

## `communities/{communityId}/gameDefinitions/{gameDefinitionId}`

Custom game-type schema entries scoped to one league (Phase E1). These are league-managed definitions for naming + rules text; game logs can later reference them in Phase E2+.

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | server | yes | Must equal `gameDefinitionId`. |
| `communityId` | string | yes | no | none | server | yes | Must equal parent `communityId`. |
| `name` | string | yes | no | none | server | no | Non-empty display name; max length 80 (callable validation). |
| `rulesText` | string | no | yes | `null` | server | no | Optional markdown/plaintext rules body; max length 8000 (callable validation). |
| `createdByProfileId` | string | yes | no | none | server | yes | Member who created the definition (callable caller uid). |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "gd_pong_plus",
  "communityId": "community_001",
  "name": "Pong Plus",
  "rulesText": "11 cups. Bounce counts as 2.",
  "createdByProfileId": "uid_abc123",
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### `gameDefinitions` invariants

- `name` is required and must be non-empty after trim.
- `communityId` must match the parent path segment.
- Definitions are create/update/delete via trusted callables in v1; clients are read-only.

---

## `memberships/{membershipId}`

Recommended ID format: `{communityId}_{profileId}` for uniqueness.

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | server | yes | Must equal `membershipId`. |
| `communityId` | string | yes | no | none | server | yes | Must reference existing community. |
| `profileId` | string | yes | no | none | server | yes | Must reference existing profile. |
| `displayName` | string | no | no | `""` | server | no | Denormalized roster field for community member lists (read-only from client). |
| `profilePhotoUrl` | string | no | yes | `null` | server | no | Denormalized roster field (read-only from client). |
| `joinedAt` | timestamp | yes | no | server timestamp | server | yes | Set once when membership is created. |
| `communityOdds` | number | no | no | `0` | server | no | Derived field; scoped to community+profile. |
| `communityGamesPlayed` | number | no | no | `0` | server | no | Count of eligible in-community game logs for this profile. Used to detect sparse data for odds-based seeding fallback (T09.4). |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "community_001_uid_abc123",
  "communityId": "community_001",
  "profileId": "uid_abc123",
  "displayName": "Maya",
  "profilePhotoUrl": null,
  "joinedAt": "SERVER_TIMESTAMP",
  "communityOdds": 0,
  "communityGamesPlayed": 0,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

---

## `communities/{communityId}/messages/{messageId}`

Single chronological thread per league (Phase C). Document ID `messageId` is typically a Firestore auto-generated id from the client on create.

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `messageId`. |
| `communityId` | string | yes | no | none | client | yes | Must equal parent `communityId`; denormalized for queries and rules. |
| `authorProfileId` | string | yes | no | none | client | yes | Must equal `auth.uid` on create (enforced in Firestore rules in Phase C2). |
| `text` | string | yes | no | none | client | no | Non-empty body; recommend max length **4000** characters (enforce in rules / client in C2/C3). |
| `deleted` | boolean | no | no | `false` | either | no | When `true`, message is soft-hidden for moderation / UX; list queries may filter `deleted == false` (C3). |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "msg_auto_id_001",
  "communityId": "community_001",
  "authorProfileId": "uid_abc123",
  "text": "Anyone up for doubles tonight?",
  "deleted": false,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### `messages` invariants

- `authorProfileId` must match the authenticated user on create (`profileId == auth.uid` V1 identity model).
- `communityId` must match the parent community document id.
- `text` must be non-empty after trim; max length 4000 (recommended contract for rules in C2).
- `deleted` is optional on legacy docs; when absent, treat as `false` in clients.

### `messages` security (Phase C2)

Rules in [firebase/firestore.rules](../../firebase/firestore.rules): community **members** may **read** and **create** messages under `communities/{communityId}/messages/*` when not blocked by `leagueHiddenForMember`; **no client update/delete** in v1 (moderation via Admin SDK / Phase D).

### `messages` indexes (Phase C3)

Composite **collection group** indexes on `messages` are in [firebase/firestore.indexes.json](../../firebase/firestore.indexes.json): `deleted ASC` + `createdAt DESC`, and a three-field index adding `__name__ DESC` for stable pagination with `orderBy(documentId)` (matches iOS `LeagueBoardView` queries).

---

## `gameLogs/{gameLogId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `gameLogId`. |
| `communityId` | string | yes | no | none | client | yes | Community where game occurred. |
| `bracketId` | string | no | yes | `null` | client | yes | Optional; when set, `bracketMatchId` must also be set and both values are immutable. |
| `bracketMatchId` | string | no | yes | `null` | client | yes | Optional; when set, `bracketId` must also be set and it must match a `matchId` within `brackets/{bracketId}`. |
| `gameType` | string enum | yes | no | none | client | yes | Built-ins: `PONG \| BEER_BALL \| BATTLE_PONG \| BASEBALL \| CROSSFIRE`. Per-league custom: literal **`CUSTOM`** (Phase E2–E3). |
| `customGameDefinitionId` | string | no | yes | `null` | client | yes | When `gameType == CUSTOM`, required non-empty string (doc id under `communities/{communityId}/gameDefinitions/*`). Omitted or `null` for built-in types. |
| `customGameDefinitionName` | string | no | yes | `null` | client | yes | Optional when `gameType == CUSTOM`: denormalized definition display name at create time (feed / profile history). Max length 80; must not be set for built-in `gameType` values. Immutable after create. |
| `createdByProfileId` | string | yes | no | none | server | yes | Creator/owner of log. |
| `participantProfileIds` | array<string> | yes | no | none | client | no | Must be unique IDs. |
| `winnerProfileIds` | array<string> | yes | no | none | client | no | Min length 1. |
| `loserProfileIds` | array<string> | yes | no | none | client | no | Min length 1. |
| `mvpProfileId` | string | no | yes | `null` | client | no | Optional; must be one of `participantProfileIds` when present. |
| `lvpProfileId` | string | no | yes | `null` | client | no | Optional; must be one of `participantProfileIds` when present. |
| `photoUrls` | array<string> | yes | no | none | client | no | Exactly one URL (concatenated front+back image). |
| `notes` | string | no | yes | `null` | client | no | Optional free-text note. |
| `pongStats` | object | no | yes | `null` | client | no | Required for strict `PONG` validation in UI. |
| `pongStats.cupMode` | number | no | no | none | client | no | Must be `6` or `10`. |
| `pongStats.playerCupsHit` | map<string, number> | no | yes | `null` | client | no | Map of profileId to integer cups hit. Sum must equal `cupMode`. |
| `pongStats.lastCupByProfileId` | string | no | yes | `null` | client | no | Must be one of `participantProfileIds` when present. |
| `beerBallStats` | object | no | yes | `null` | client | no | Optional placeholder stats for `BEER_BALL`. |
| `beerBallStats.newCanCountByProfileId` | map<string, number> | no | yes | `null` | client | no | Integer >= 0 for each participant. |
| `beerBallStats.firstFinishedByProfileId` | string | no | yes | `null` | client | no | Must be one of `participantProfileIds` when present. |
| `battlePongStats` | object | no | yes | `null` | client | no | Optional placeholder stats for `BATTLE_PONG`. |
| `battlePongStats.playerCupsHit` | map<string, number> | no | yes | `null` | client | no | Integer >= 0 for each participant. |
| `baseballStats` | object | no | yes | `null` | client | no | Optional placeholder stats for `BASEBALL`. |
| `baseballStats.hitsByProfileId` | map<string, number> | no | yes | `null` | client | no | Integer >= 0 for each participant. |
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
  "mvpProfileId": "uid_abc123",
  "lvpProfileId": "uid_def456",
  "photoUrls": ["https://storage.googleapis.com/bcup/logs/gameLog_001/photo1.jpg"],
  "notes": "Close game.",
  "pongStats": {
    "cupMode": 10,
    "playerCupsHit": {
      "uid_abc123": 8,
      "uid_def456": 5
    },
    "lastCupByProfileId": "uid_abc123"
  },
  "beerBallStats": null,
  "battlePongStats": null,
  "baseballStats": null,
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

### `gameLogs` invariants

- `winnerProfileIds.length >= 1`
- `loserProfileIds.length >= 1`
- `photoUrls.length == 1` (single concatenated image URL)
- `bracketId` and `bracketMatchId` are either both present (non-empty strings) or both absent.
- when `bracketId` / `bracketMatchId` are set, the log’s `participantProfileIds`, `winnerProfileIds`, and `loserProfileIds` must partition the referenced bracket match’s `participantProfileIds` (server-enforced by bracket sync logic).
- `winnerProfileIds` is a subset of `participantProfileIds`
- `loserProfileIds` is a subset of `participantProfileIds`
- No overlap between winners and losers
- No duplicates in `participantProfileIds`, `winnerProfileIds`, or `loserProfileIds`
- `mvpProfileId` must be in `participantProfileIds` when present
- `lvpProfileId` must be in `participantProfileIds` when present
- `mvpProfileId != lvpProfileId` when both are present
- `pongStats.cupMode` is either `6` or `10` when `gameType == PONG`
- Sum of `pongStats.playerCupsHit` equals `pongStats.cupMode` when `gameType == PONG`
- `pongStats.lastCupByProfileId` must be in `participantProfileIds` when present
- **Custom games (E2):** When `gameType == CUSTOM`, `customGameDefinitionId` must be a non-empty string (Firestore rules). Built-in `gameType` values must not set `customGameDefinitionId` to a non-null value. `gameType` and `customGameDefinitionId` are immutable after create. When present, `customGameDefinitionName` is a non-empty string (max 80) for `CUSTOM` only; built-in logs must not set it; it is immutable after create.
- **Odds maps:** `profiles.overallOddsByGameType` / `memberships.communityOddsByGameType` include built-in keys plus dynamic keys `CUSTOM:{customGameDefinitionId}` for custom logs, and optionally `OTHER:{gameType}` for legacy unknown `gameType` strings without a definition id (server `functions/src/oddsRecalc.ts`).

---

## Image Delivery Contract (`T13.2`)

- Storage originals are the source of truth:
  - `profiles.profilePhotoUrl`
  - `gameLogs.photoUrls[0]` (single item)
- Clients may derive transformed URLs for display surfaces; originals remain persisted data.
- Current iOS variant contract:
  - `feedThumb`: append `_800x800` before extension
  - `avatar`: append `_400x400` before extension
  - `full`: original URL
- Fallback rule: if transformed URL cannot be built or fetch fails, use original URL.
- Upload metadata requirement for photo objects:
  - `Cache-Control: public,max-age=31536000,immutable`
- Format/quality policy:
  - Prefer modern compressed formats when supported by transformation pipeline.
  - Use auto/tuned quality in resize extension configuration.

---

## `brackets/{bracketId}`

| Field | Type | Required | Nullable | Default | Set by | Immutable | Notes |
|---|---|---|---|---|---|---|---|
| `id` | string | yes | no | none | either | yes | Must equal `bracketId`. |
| `communityId` | string | yes | no | none | client | yes | Scope for participants and odds. |
| `participantProfileIds` | array<string> | yes | no | none | server | no | Auto-populate from current members at creation. |
| `seedMethod` | string enum | yes | no | none | client | yes | `COMMUNITY_ODDS \| MANUAL \| RANDOM`. |
| `teamSize` | number | yes | no | none | server | yes | Integer 1–4; players per side in each match. Set at creation. |
| `status` | string enum | yes | no | `DRAFT` | client | no | `DRAFT \| ACTIVE \| COMPLETE`. |
| `rounds` | array<object> | yes | no | `[]` | server | no | See **Bracket `rounds` structure** below. |
| `createdAt` | timestamp | yes | no | server timestamp | server | yes | Global rule. |
| `updatedAt` | timestamp | yes | no | server timestamp | server | no | Global rule. |

Canonical valid sample:

```json
{
  "id": "bracket_001",
  "communityId": "community_001",
  "participantProfileIds": ["uid_abc123", "uid_def456", "uid_ghi789", "uid_jkl012"],
  "seedMethod": "COMMUNITY_ODDS",
  "teamSize": 1,
  "status": "DRAFT",
  "rounds": [],
  "createdAt": "SERVER_TIMESTAMP",
  "updatedAt": "SERVER_TIMESTAMP"
}
```

**At creation:** `COMMUNITY_ODDS` and `RANDOM` are written with non-empty `rounds` and `status` **`ACTIVE`** by the server. `MANUAL` is written with empty `rounds` and **`DRAFT`** until `finalizeManualBracket`.

### Bracket `rounds` structure

`rounds` is an **array of rounds**. Each element:

| Field | Type | Notes |
|---|---|---|
| `roundNumber` | number | Integer ≥ 1, unique within the bracket’s `rounds` array (1-based). |
| `matches` | array<object> | Matches in this round; see **Match object** below. |

`matchId` values must be **unique across all matches** in the bracket (all rounds).

### Bracket match object (2v2-friendly)

Align outcome fields with `gameLogs` where results are attributed.

| Field | Type | Notes |
|---|---|---|
| `matchId` | string | Stable id within the bracket. |
| `roundNumber` | number | Same logical round as the parent `rounds[]` entry (redundant but supports flat lookups). |
| `participantProfileIds` | array<string> | Everyone in the match; minimum length 2 (1v1 or 2v2). |
| `winnerProfileIds` | array<string> | **Omit** when the match is unplayed. When present, `loserProfileIds` must also be present. Min length 1 when present. |
| `loserProfileIds` | array<string> | **Omit** when unplayed. When present, `winnerProfileIds` must also be present. Min length 1 when present. |
| `feederMatchIds` | array<string> | **Optional.** Exactly two `matchId` strings for round 2+ placeholders when `participantProfileIds` is empty; omit on round 1 matches. |

**Unplayed matches:** omit both `winnerProfileIds` and `loserProfileIds` entirely. Do **not** persist these keys with empty arrays `[]` for unplayed matches (empty array is invalid for a recorded result).

**Played matches:** both arrays must be present, each length ≥ 1.

**Invariants (same as `gameLogs`):** `winnerProfileIds` and `loserProfileIds` are subsets of `participantProfileIds`; sets are disjoint; no duplicate ids within each array.

Server-side validation reference: `functions/src/bracketModel.ts` (`validateBracketMatch`, `validateRoundsStructure`).

Firestore security rules only enforce **top-level** bracket keys (`hasBracketKeys`); **nested** match validation should be enforced in **Cloud Functions** (or the client) when implementing `updateMatchResult`.

---

## Derived fields ownership

- `profiles.overallOdds`: computed by Cloud Functions on game log create/update/delete.
- `profiles.overallGamesPlayed`: computed by Cloud Functions alongside `overallOdds` on game log create/update/delete.
- `memberships.communityOdds`: computed by Cloud Functions on game log create/update/delete.
- `memberships.communityGamesPlayed`: computed by Cloud Functions alongside `communityOdds` on game log create/update/delete. Used to detect sparse community data for odds-based seeding fallback (T09.4).

Clients should treat derived fields as read-only.

## Query/index checklist (minimum)

- `memberships`: `profileId ASC, joinedAt DESC`
- `memberships`: `communityId ASC, joinedAt ASC`
- `gameLogs`: `communityId ASC, createdAt DESC, __name__ DESC` — required for home feed and per-community feed: `orderBy createdAt` + `orderBy documentId` for stable cursors (`DependencyContainer` feed services; chunk size 10 for `in` on `communityId`).
- `gameLogs`: `participantProfileIds CONTAINS, communityId ASC` — `computeCommunityOdds` / rules-aligned odds paths in `functions/src/oddsRecalc.ts` (no `orderBy`).
- `gameLogs`: `createdByProfileId ASC, createdAt DESC` — **not** referenced by current client/functions queries; keep for documented “my logs” listing if added later (`data-contracts` / specs).
- `brackets`: `communityId ASC, createdAt DESC` — **not** referenced by current codebase (bracket UI uses document listener by id); keep for future list-by-community queries.
- `communities`: `inviteCode ASC` (single-field; typically auto-indexed for equality + `limit(1)` in `functions/src/communities.ts`)
- `communities/{communityId}/gameDefinitions`: `createdAt DESC` (single-field index for ordered list)

### Firestore performance notes (T11.5)

**Index deploy:** After changing [`firebase/firestore.indexes.json`](../../firebase/firestore.indexes.json), deploy with:

```bash
firebase deploy --only firestore:indexes
```

(from repo root; uses [`firebase.json`](../../firebase.json) → `firestore.indexes`).

**High-volume client reads (iOS, `DependencyContainer` — read-only audit, no code change here):**

| Path | Query pattern | Cost notes |
|------|----------------|------------|
| Home feed | `memberships` where `profileId == uid` (full scan of memberships for user) → chunked `gameLogs` where `communityId in (≤10)` · `orderBy createdAt, documentId desc` · `limit` (50) per chunk; merge client-side | Read counts scale with **number of communities** (one query per chunk per page). N+1: **display names** — `fetchProfileDisplayNamesMap` / `fetchCommunityNamesMap` issue **one `getDocument` per unique id** per page (parallelized). |
| Community feed | `gameLogs` where `communityId ==` · same order/limit | Favorable: single query + name maps. |
| Community roster | `memberships` where `communityId ==` (no limit) + optional profile reads for self only | Membership doc count = **member count** per open roster. |
| Communities list | `memberships` where `profileId ==` · `orderBy documentId` · paginate 25 + parallel `communities/{id}` gets | Stable pagination; community gets parallelized. |

**Profile aggregates (`ProfileView`):** `fetchAllFeedRows()` loops `fetchFeedPage` until exhausted (page size 50) to compute stats — **read count grows with all game logs across the user’s leagues** (worst case unbounded). Mitigations to consider later: server-maintained aggregates, capped pages with explicit UX, or callable that returns counts.

**Cloud Functions (partner-sensitive seeds — document only):** `buildH2HMap` in `functions/src/bracketSeeding.ts` loads **all** `gameLogs` for a `communityId` with no `limit` — payload and read cost scale with league history. `computeOverallOdds` uses `array-contains` on `participantProfileIds` with no community filter — scans **global** logs for that user profile.

**Realtime listeners:** `BracketsView` attaches a **single-document** listener on `brackets/{id}` — bounded payload (full bracket tree in one doc; large for big tournaments — acceptable for v1 if bracket docs stay under Firestore’s 1 MiB doc limit).

### Threat model (T11.6)

Lightweight review of **unauthorized access** and **abuse** against the **Firebase + iOS** surface described in this doc, [`firebase/firestore.rules`](../../firebase/firestore.rules), [`firebase/storage.rules`](../../firebase/storage.rules), and [`docs/architecture/api-contracts.md`](api-contracts.md). Likelihood / impact are qualitative (**L/M/H**).

#### Trust boundaries (never trust the client alone)

| Client-submitted data | Server enforcement today | Gap |
|----------------------|--------------------------|-----|
| `gameLogs` outcomes (`participantProfileIds`, winners/losers, MVP/LVP) | Rules: creator = `uid()`, member of `communityId`, array sizes & MVP/LVP ∈ participants | Rules do **not** prove participants are **community members** or that outcomes match a real match; integrity relies on honest clients + social recovery. |
| `brackets` shape (`rounds`, `status`, `seedMethod`, `teamSize`) | Rules: member of `communityId`; key whitelist; `id` / `communityId` / `createdAt` immutable on update | **Any** league member may **update** bracket `rounds` and `status` (see Firestore `brackets` `update`). Not narrowed to creator/admin/callable-only. |
| `profiles` odds / games played | Rules: client cannot change `overallOdds` / `overallGamesPlayed` on update | OK — derived fields server-owned. |
| `communities` invite metadata | Client updates: name only; `inviteCode` / `inviteLink` immutable | OK. New codes issued only via Admin/callables. |
| Storage paths | `gamePhotos/{communityId}/{gameLogId}/{fileName}` + metadata `createdByProfileId` | Path uses `gameLogId`; client must align with Firestore doc id (coordination). Size/type caps in rules. |
| Callable payloads (`createCommunity`, `joinCommunity`, etc.) | `functions/src/communities.ts`, `brackets.ts`, `bracketManualSeed.ts`, `bracketGameLogSync.ts`: `request.auth`, validation | **No Firebase App Check** in repo — callables are **authenticated user** surface only, not bot-resistant. |

#### Risk register (summary)

| Threat | Affected component | L / I | Mitigation (existing vs recommended) |
|--------|--------------------|-------|--------------------------------------|
| Member tampering with bracket progression or structure | Firestore `brackets` client `update` | M / H | **Existing:** none in rules for structural validation. **Recommended:** restrict `rounds`/`status` updates to **Admin / trusted callables** only; client read-only except DRAFT manual seed if needed. |
| Fabricated or mistaken `gameLogs` opponents / results | Firestore `gameLogs` `create`/`update` | M / M | **Existing:** membership + key checks. **Recommended:** optional **callable** validation against roster or bracket match; or post-hoc moderation / reporting. |
| Roster / odds fields visible to all members | Firestore `memberships` **read** if `isCommunityMember(communityId)` | L / M | **Existing:** by design for roster (`displayName` denormalized). **Recommended:** document product expectation; avoid extra PII on membership docs. |
| Profile photo URLs readable by any signed-in user who guesses path | Storage `profilePhotos/{profileId}/**` **read: signedIn** | M / M | **Existing:** any authed user can read any profile object. **Recommended:** tighten to **owner-only** read **or** signed URLs with TTL if URLs leak. |
| Invite code guessing / enumeration | `previewJoinCommunity` + 8-char code ([`communities.ts`](../../functions/src/communities.ts)) | L / L–M | **Existing:** random unambiguous alphabet, uniqueness check. **Recommended:** rate-limit / CAPTCHA on preview + join callables; lockout after N failures (server-side). |
| Spam: communities, brackets, game logs, uploads | Callables + rules allow writes for members | M / M | **Existing:** community **member cap** (350) in `createCommunity` / join transaction. **Recommended:** **App Check** on callables; per-user rate limits; monitor Firestore/Storage **quotas** and **functions** invocations (see T11.5 cost notes). |
| Amplified backend cost from game log churn | `onGameLogCreated` / `Updated` / `Deleted` → odds + bracket sync | M / M | **Existing:** triggers always run. **Recommended:** idempotent handlers (already important); batch/alarm on errors; consider debounce for odds if workloads grow. |
| `GoogleService-Info.plist` / API keys in repo | iOS client config | L / L | **Existing:** typical for mobile Firebase; rules enforce access. **Recommended:** separate **dev/prod** projects and plists; never commit **service account JSON**; CI uses **workload identity** / secrets manager for deploy keys. |

#### Secrets & config

- **Client:** `GoogleService-Info.plist` exposes project id, app id, API key — expected for Firebase SDK; **security is rules + Auth**, not hiding the plist.
- **Server:** Cloud Functions use Admin SDK; keys belong in **GCP / Firebase** runtime only, not in git.
- **CI:** [.github/workflows/*.yml](../../.github/workflows/) should not embed deploy tokens in logs; use GitHub **encrypted secrets** for `firebase deploy`.

---

## Change control

- **Breaking change policy:** schema changes require updating this doc and adding a migration note in the PR.
- Any schema change must update this file before implementation.
- If a field is renamed/removed, include a migration note in PR description.
