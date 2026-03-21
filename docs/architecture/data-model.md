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