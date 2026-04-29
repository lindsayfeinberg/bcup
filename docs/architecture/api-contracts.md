# API Contracts

## Standard Envelopes

### Success (all callables)
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {},
  "meta": {
    "requestId": "string"
  }
}
```

### Error (all callables)
```json
{
  "ok": false,
  "apiVersion": "v1",
  "error": {
    "code": "UNAUTHENTICATED | INVALID_ARGUMENT | PERMISSION_DENIED | NOT_FOUND | ALREADY_EXISTS | INTERNAL",
    "message": "string",
    "details": "string | null",
    "requestId": "string"
  }
}
```

---

## Auth

### `onUserCreated`
- **Trigger:** Firebase Auth `onCreate` (background, not callable)
- **Auth:** None required
- **Action:** Creates `profiles/{userId}` document on first Google sign-in
- **Input:** Firebase Auth user object (automatic)
- **Output:** `profiles/{userId}` document created — no response envelope

---

## Communities

### `createCommunity`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated
- **Validation:** `name` must be non-empty string

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "name": "Sunday Funday"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "inviteCode": "XYZ99",
    "inviteLink": "https://bcup.app/join/XYZ99"
  },
  "meta": { "requestId": "req_001" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`

---

### `joinCommunity`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated
- **Validation:** `inviteCode` must match an existing community; user must not already be a member

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "inviteCode": "XYZ99"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123"
  },
  "meta": { "requestId": "req_002" }
}
```

**Errors:** `UNAUTHENTICATED`, `NOT_FOUND`, `ALREADY_EXISTS`, `FAILED_PRECONDITION` (community already at the 350-member cap)

---

### `listGameDefinitions`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and an eligible community member (hidden-league behavior matches other member reads)
- **Validation:** `communityId` required

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "items": [
      {
        "gameDefinitionId": "gd_pong_plus",
        "name": "Pong Plus",
        "rulesText": "11 cups. Bounce counts as 2.",
        "createdByProfileId": "uid_1",
        "createdAtMillis": 1714060800000,
        "updatedAtMillis": 1714060800000
      }
    ]
  },
  "meta": { "requestId": "req_002a" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `NOT_FOUND`

---

### `createGameDefinition`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and an eligible community member (same hidden-league rules as `listGameDefinitions`)
- **Validation:** `communityId` and non-empty `name` required; `name <= 80`; optional `rulesText <= 8000`

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "name": "Pong Plus",
    "rulesText": "11 cups. Bounce counts as 2."
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "gameDefinitionId": "gd_pong_plus"
  },
  "meta": { "requestId": "req_002b" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `NOT_FOUND`

---

### `updateGameDefinition`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and an eligible community member (same hidden-league rules as `listGameDefinitions`)
- **Validation:** `communityId`, `gameDefinitionId`, and non-empty `name` required; same length limits as create

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "gameDefinitionId": "gd_pong_plus",
    "name": "Pong Plus (v2)",
    "rulesText": "Updated rule text"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "gameDefinitionId": "gd_pong_plus"
  },
  "meta": { "requestId": "req_002c" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `NOT_FOUND`

---

### `deleteGameDefinition`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and an eligible community member (same hidden-league rules as `listGameDefinitions`)
- **Validation:** `communityId` and `gameDefinitionId` required

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "gameDefinitionId": "gd_pong_plus"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "gameDefinitionId": "gd_pong_plus"
  },
  "meta": { "requestId": "req_002d" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `NOT_FOUND`

---

## Game Logs

### `createGameLog`
- **Trigger:** Firestore document create (`gameLogs/{gameLogId}`) by an authenticated client (via `setData`)
- **Auth:** Must be authenticated and a member of `communityId`
- **Validation:**
  - `winnerProfileIds` and `loserProfileIds` min length 1
  - Both must be subsets of `participantProfileIds`
  - No profile can appear in both winners and losers
  - `photoUrls` min length 1
  - Optional bracket linkage:
    - `bracketId` and `bracketMatchId` are either both set (non-empty) or both omitted
    - when set, bracket match progression is applied by Cloud Functions trigger (non-primary “backfill-only” callable exists for repair)
  - `pongStats` required only when `gameType` is `PONG`, with:
    - `cupMode` in `{6, 10}`
    - sum of `playerCupsHit` equal to `cupMode`
    - optional `lastCupByProfileId` in participants
  - Optional placeholders:
    - `beerBallStats.newCanCountByProfileId`, optional `beerBallStats.firstFinishedByProfileId`
    - `battlePongStats.playerCupsHit`
    - `baseballStats.hitsByProfileId`
  - **Per-league custom game (Phase E2):** `gameType` may be **`CUSTOM`** with required `customGameDefinitionId` (id of `communities/{communityId}/gameDefinitions/{id}`). Built-in `gameType` values must omit `customGameDefinitionId` or set it to `null`. Both fields are immutable after create (Firestore rules).

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "gameType": "PONG",
    "participantProfileIds": ["uid_1", "uid_2"],
    "winnerProfileIds": ["uid_1"],
    "loserProfileIds": ["uid_2"],
    "photoUrls": ["https://storage.firebase.com/photo1.jpg"],
    "notes": null,
    "pongStats": {
      "cupMode": 10,
      "playerCupsHit": { "uid_1": 10, "uid_2": 6 }
    },
    "beerBallStats": null,
    "battlePongStats": null,
    "baseballStats": null
  }
}
```

**Custom game log (same write path, `setData` on `gameLogs/{gameLogId}`):**

```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "gameType": "CUSTOM",
    "customGameDefinitionId": "gd_pong_plus",
    "participantProfileIds": ["uid_1", "uid_2"],
    "winnerProfileIds": ["uid_1"],
    "loserProfileIds": ["uid_2"],
    "photoUrls": ["https://storage.firebase.com/photo1.jpg"],
    "notes": null,
    "pongStats": null,
    "beerBallStats": null,
    "battlePongStats": null,
    "baseballStats": null,
    "crossfireStats": null
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "gameLogId": "log_abc"
  },
  "meta": { "requestId": "req_003" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`

---

### `updateGameLog`
- **Trigger:** Firestore document update (`gameLogs/{gameLogId}`) by the authenticated log creator
- **Auth:** Must be authenticated and the original log creator
- **Validation:** Same field rules as `createGameLog`

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "gameLogId": "log_abc",
    "photoUrls": ["https://storage.firebase.com/photo2.jpg"],
    "notes": "Updated note"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {},
  "meta": { "requestId": "req_004" }
}
```

**Errors:** `UNAUTHENTICATED`, `PERMISSION_DENIED`, `NOT_FOUND`

---

### `deleteGameLog`
- **Trigger:** Firestore document delete (`gameLogs/{gameLogId}`) by the authenticated log creator
- **Auth:** Must be authenticated and the original log creator

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "gameLogId": "log_abc"
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {},
  "meta": { "requestId": "req_005" }
}
```

**Errors:** `UNAUTHENTICATED`, `PERMISSION_DENIED`, `NOT_FOUND`

---

## Odds

### `recalculateOdds`
- **Trigger:** Firestore `onCreate / onUpdate / onDelete` on `gameLogs` (background, not callable)
- **Auth:** None required
- **Input:** Firestore event (automatic)
- **Output:** Writes updated odds fields directly to Firestore — no response envelope

#### Definitions
- **Eligible game log:** exists (not deleted) and has `winnerProfileIds.length >= 1`,
  `loserProfileIds.length >= 1`, and `participantProfileIds` present
- **Win:** profile appears in `winnerProfileIds`
- **Game played:** profile appears in `participantProfileIds`
- **Precision:** store full numeric precision; UI displays 3 decimals

#### Formulas
- `overallOdds(profileId)` = `overallWins / overallGames` (0 if no games)
- `communityOdds(profileId, communityId)` = `communityWins / communityGames` (0 if no games)

#### Recalculation triggers and write targets
- Triggers on every game log create, update, and delete
- Recomputes for all impacted participants:
  - `after` snapshot participants for create/update
  - `before` snapshot participants for update/delete
- If `communityId` changes on update, recalculate both old and new communities
- Writes to:
  - `profiles/{profileId}.overallOdds`
  - `memberships/{communityId}_{profileId}.communityOdds`

#### Tie-break order (mandatory for bracket seeding and leaderboards)
1. Higher odds (`DESC`)
2. More games played (`DESC`)
3. Head-to-head wins among tied profiles (`DESC`) when available
4. Earlier `profiles.createdAt` (`ASC`)
5. Lexicographic `profileId` (`ASC`)

#### Acceptance examples
- Profile A: `wins=2, games=4` → `0.5` | Profile B: `wins=1, games=2` → `0.5` → **A wins** (more games)
- Profile C: `wins=0, games=0` → `0` | Profile D: `wins=0, games=0` → `0` → **earlier `createdAt`** wins; if still tied, lower `profileId`

---

## Brackets

### `createBracket`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and a member of `communityId`
- **Validation:**
  - `seedMethod` must be one of `COMMUNITY_ODDS`, `MANUAL`, `RANDOM`
  - `teamSize` must be an integer **1–4** (players per side)
  - Community must have at least **`2 * teamSize`** members for a full opening match
  - If `COMMUNITY_ODDS` and data is sparse, fall back to `overallOdds` (see odds seeding)

**Behavior by `seedMethod`:**
- `COMMUNITY_ODDS` — Server builds and validates `rounds`; `status` is **`ACTIVE`**.
- `MANUAL` — `rounds` is `[]`; `status` is **`DRAFT`** until `finalizeManualBracket`.
- `RANDOM` — Server deterministically shuffles the sorted participant list using **SHA-256** of the UTF-8 string `bracketId|id1|id2|…` (ids in lexicographic order as stored), then **Fisher–Yates** with a **Mulberry32** PRNG seeded from XOR of the digest’s eight little-endian uint32 words. Then `chunkIntoTeams` + standard bracket generation; `rounds` is filled and `status` is **`ACTIVE`**. Same inputs always yield the same bracket structure.

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "seedMethod": "COMMUNITY_ODDS",
    "teamSize": 1
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {
    "bracketId": "bracket_xyz"
  },
  "meta": { "requestId": "req_006" }
}
```

**Errors:** `UNAUTHENTICATED`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`

---

### `finalizeManualBracket`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and a member of the bracket’s community (`memberships/{communityId}_{uid}`)
- **Purpose:** For brackets created with `seedMethod: MANUAL`, `createBracket` leaves `status: DRAFT` and `rounds: []`. This callable accepts the organizer’s **ordered list of teams** (each team is a roster drawn from the bracket’s participants), builds rounds server-side with standard single-elimination structure, validates them, and sets `rounds` plus `status: ACTIVE`. Team order is bracket seed order (team 1 gets best bye preference, same semantics as greedy chunking of a flat list).
- **Validation:**
  - `bracketId` (non-empty string) required
  - `teams` must be a non-empty array of arrays; each inner array is a non-empty list of profile id strings
  - Bracket must exist
  - `seedMethod` must be `MANUAL`
  - `status` must be `DRAFT`
  - `rounds` must be empty (not already finalized)
  - Row **sizes** must match the greedy partition of `(N, teamSize)` where `N = len(participantProfileIds)`: repeat `min(teamSize, remaining)` until no players left (e.g. N=5, teamSize=2 → team lengths `[2, 2, 1]`)
  - Flattening `teams` in row order must be a **permutation** of `participantProfileIds` (no duplicates, no unknown ids)

**Request (example: 2v2, four players):**
```json
{
  "apiVersion": "v1",
  "data": {
    "bracketId": "bracket_xyz",
    "teams": [
      ["uid_1", "uid_2"],
      ["uid_3", "uid_4"]
    ]
  }
}
```

**Request (example: 1v1, four players):**
```json
{
  "apiVersion": "v1",
  "data": {
    "bracketId": "bracket_xyz",
    "teams": [
      ["uid_4"],
      ["uid_1"],
      ["uid_3"],
      ["uid_2"]
    ]
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {},
  "meta": { "requestId": "req_006b" }
}
```

**Errors:** `UNAUTHENTICATED`, `NOT_FOUND`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`, `INTERNAL`

---

### `updateMatchResult`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and a member of the bracket's community
- **Validation:** Same spirit as `gameLogs`: `winnerProfileIds` and `loserProfileIds` must each have length ≥ 1; both must be subsets of that match’s `participantProfileIds`; no profile in both winner and loser lists; supports **2v2** (two winners, two losers) when the match lists four participants.
- **Note:** This is a non-primary backfill/repair path. Primary bracket progression comes from `gameLogs` create with optional `bracketId` + `bracketMatchId`.

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "bracketId": "bracket_xyz",
    "matchId": "match_1",
    "winnerProfileIds": ["uid_1", "uid_2"],
    "loserProfileIds": ["uid_3", "uid_4"]
  }
}
```

**Response:**
```json
{
  "ok": true,
  "apiVersion": "v1",
  "data": {},
  "meta": { "requestId": "req_007" }
}
```

**Errors:** `UNAUTHENTICATED`, `NOT_FOUND`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`