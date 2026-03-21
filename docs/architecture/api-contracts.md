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

**Errors:** `UNAUTHENTICATED`, `NOT_FOUND`, `ALREADY_EXISTS`

---

## Game Logs

### `createGameLog`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and a member of `communityId`
- **Validation:**
  - `winnerProfileIds` and `loserProfileIds` min length 1
  - Both must be subsets of `participantProfileIds`
  - No profile can appear in both winners and losers
  - `photoUrls` min length 1
  - `pongStats` required only when `gameType` is `PONG`

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
      "playerCupsHit": { "uid_1": 10, "uid_2": 6 }
    }
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
- **Trigger:** HTTPS callable
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
- **Trigger:** HTTPS callable
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
  - If `COMMUNITY_ODDS` and data is sparse, fall back to `overallOdds`

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "communityId": "abc123",
    "seedMethod": "COMMUNITY_ODDS"
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

### `updateMatchResult`
- **Trigger:** HTTPS callable
- **Auth:** Must be authenticated and a member of the bracket's community
- **Validation:** `winnerId` must be one of the two participants in the match

**Request:**
```json
{
  "apiVersion": "v1",
  "data": {
    "bracketId": "bracket_xyz",
    "matchId": "match_1",
    "winnerId": "uid_1"
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