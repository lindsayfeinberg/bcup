# Data Model

## Collections

### `profiles`
```
profiles/{userId}
  - id: UUID
  - googleAuthId: string
  - displayName: string
  - profilePhotoUrl: string | null
  - overallOdds: decimal (computed)
  - ageConfirmed21PlusAt: timestamp | null
  - onboardingCompleteAt: timestamp | null
  - createdAt: timestamp
  - updatedAt: timestamp
```

### `communities`
```
communities/{communityId}
  - id: UUID
  - name: string
  - createdByProfileId: UUID
  - inviteCode: string (unique)
  - inviteLink: string
  - createdAt: timestamp
  - updatedAt: timestamp
```

### `memberships`
```
memberships/{communityId}_{profileId}
  - communityId: UUID
  - profileId: UUID
  - communityOdds: decimal (computed, cached)
  - joinedAt: timestamp
```

### `gameLogs`
```
gameLogs/{gameLogId}
  - id: UUID
  - communityId: UUID
  - gameType: enum (PONG, BEER_BALL, BATTLE_PONG, BASEBALL)
  - createdByProfileId: UUID
  - participantProfileIds: array<UUID>
  - winnerProfileIds: array<UUID> (min 1)
  - loserProfileIds: array<UUID> (min 1)
  - photoUrls: array<string> (min 1)
  - notes: string | null
  - createdAt: timestamp
  - updatedAt: timestamp

  subcollection: pongStats/{gameLogId}
    - gameLogId: UUID
    - playerCupsHit: map<profileId -> integer>
```

### `brackets`
```
brackets/{bracketId}
  - id: UUID
  - communityId: UUID
  - participantProfileIds: array<UUID> (auto all members)
  - seedMethod: enum (COMMUNITY_ODDS, MANUAL, RANDOM)
  - rounds: array (structured rounds/matches; each match can use winnerProfileIds/loserProfileIds arrays for team/2v2 outcomes — see data-contracts)
  - status: enum (DRAFT, ACTIVE, COMPLETE)
  - createdAt: timestamp
  - updatedAt: timestamp
```

---

## Enums and Constants

### GameType
- `PONG`
- `BEER_BALL`
- `BATTLE_PONG`
- `BASEBALL`

### SeedMethod
- `COMMUNITY_ODDS`
- `MANUAL`
- `RANDOM`

### BracketStatus
- `DRAFT`
- `ACTIVE`
- `COMPLETE`

### Derived Calculations
- `overallOdds = totalWins / totalGames` (across all communities)
- `communityOdds = communityWins / communityGames` (scoped to one community)
- Display precision: 2–3 decimal places

---

## Onboarding Flags

Both flags live on `profiles/{userId}`.

| Field | Type | Description |
|---|---|---|
| `ageConfirmed21PlusAt` | timestamp or null | Set once when user confirms `I am 21+` on first login. Null if not yet confirmed. |
| `onboardingCompleteAt` | timestamp or null | Set once all required profile fields are filled (displayName, profilePhoto). Null if incomplete. |

### Rules
- Both fields are set once and never reset.
- If `onboardingCompleteAt` is non-null, skip onboarding and route directly to home feed.
- If `ageConfirmed21PlusAt` is null, show age gate before anything else.
- If `onboardingCompleteAt` is null but `ageConfirmed21PlusAt` is set, resume at profile setup step.