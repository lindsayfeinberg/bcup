# API Contracts

All Cloud Functions return the following envelope on error:
```json
{
  "error": {
    "code": "string",
    "message": "string"
  }
}
```

---

## Auth

### `onUserCreated`
- **Trigger:** Firebase Auth `onCreate`
- **Action:** Creates a `profiles` document for the new user
- **Input:** Firebase Auth user object
- **Output:** `profiles/{userId}` document created

---

## Communities

### `createCommunity`
- **Trigger:** HTTPS callable
- **Input:**
```json
  { "name": "string" }
```
- **Output:**
```json
  { "communityId": "string", "inviteCode": "string", "inviteLink": "string" }
```
- **Errors:** `unauthenticated`, `invalid-argument`

### `joinCommunity`
- **Trigger:** HTTPS callable
- **Input:**
```json
  { "inviteCode": "string" }
```
- **Output:**
```json
  { "communityId": "string" }
```
- **Errors:** `unauthenticated`, `not-found`, `already-exists`

---

## Game Logs

### `createGameLog`
- **Trigger:** HTTPS callable
- **Input:**
```json
  {
    "communityId": "string",
    "gameType": "PONG | BEER_BALL | BATTLE_PONG | BASEBALL",
    "participantProfileIds": ["string"],
    "winnerProfileIds": ["string"],
    "loserProfileIds": ["string"],
    "photoUrls": ["string"],
    "notes": "string | null",
    "pongStats": { "playerCupsHit": { "profileId": "integer" } }
  }
```
- **Output:**
```json
  { "gameLogId": "string" }
```
- **Errors:** `unauthenticated`, `invalid-argument`, `permission-denied`

### `updateGameLog`
- **Trigger:** HTTPS callable
- **Input:** Same as `createGameLog` plus `"gameLogId": "string"`
- **Output:** `{ "success": true }`
- **Errors:** `unauthenticated`, `permission-denied` (non-creator), `not-found`

### `deleteGameLog`
- **Trigger:** HTTPS callable
- **Input:** `{ "gameLogId": "string" }`
- **Output:** `{ "success": true }`
- **Errors:** `unauthenticated`, `permission-denied` (non-creator), `not-found`

---

## Odds

### `recalculateOdds`
- **Trigger:** Firestore `onCreate / onUpdate / onDelete` on `gameLogs`
- **Action:** Recomputes `overallOdds` on profile and `communityOdds` on membership
- **Input:** Firestore event (automatic)
- **Output:** Updates `profiles/{userId}.overallOdds` and `memberships/{id}.communityOdds`

---

## Brackets

### `createBracket`
- **Trigger:** HTTPS callable
- **Input:**
```json
  { "communityId": "string", "seedMethod": "COMMUNITY_ODDS | MANUAL | RANDOM" }
```
- **Output:**
```json
  { "bracketId": "string" }
```
- **Errors:** `unauthenticated`, `invalid-argument`, `permission-denied`

### `updateMatchResult`
- **Trigger:** HTTPS callable
- **Input:**
```json
  { "bracketId": "string", "matchId": "string", "winnerId": "string" }
```
- **Output:** `{ "success": true }`
- **Errors:** `unauthenticated`, `not-found`, `invalid-argument`