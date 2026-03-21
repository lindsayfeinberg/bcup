# bcup - V1 Product Requirements Document (PRD)

## Project overview

`bcup` is an iPhone app for private drinking-game communities that combines:

1. Social logging of games with required photo evidence
2. Competitive tracking through odds and community brackets

V1 is intentionally scoped around private communities and `Pong` as the most fully defined game experience, while still allowing logging for `Beer Ball`, `Battle Pong`, and `Baseball`.

### Problem statement
- Existing drinking-game tracking is fragmented across group chats, notes, and memory.
- There is no private, structured way to log outcomes, compare performance, and run recurring brackets with the same friend groups.

### Vision
- Make game-night history and competition easy to capture, trustworthy, and fun.
- Build a social record for each community with stats that create friendly rivalry.

### V1 goals
- Enable invite-only communities where friends can log games and browse a shared feed.
- Support reliable game logs with required photos and clear winner/loser attribution.
- Calculate both per-community and overall odds.
- Run seeded brackets using user-selected seeding methods.

### V1 non-goals
- Public discovery/community browsing
- Advanced moderation tooling
- Deep rule engines for non-Pong game types
- Complex role/permission hierarchy beyond equal member permissions

### Success metrics (V1)
- Community activation rate: % of created communities with at least 3 members
- Logging activation: % of new users posting at least one game log in first 7 days
- Weekly retention: % of users returning weekly to view feed or log games
- Content quality: % of logs with complete required fields and valid photos
- Competitive engagement: average number of bracket updates viewed per active user

## Canonical architecture docs

- Data model and enums: `docs/architecture/data-model.md`
- Firestore data contracts: `docs/architecture/data-contracts.md`
- Cloud Functions API contracts: `docs/architecture/api-contracts.md`

## Core requirements

### Authentication and onboarding
- Users sign in via Google.
- Users complete a self-confirmation age gate (`I am 21+`) on first successful login only.
- Users can edit `displayName` and `profilePhoto`.
- App persists onboarding completion state per user and skips repeated onboarding steps on returning sessions.

### Privacy and membership model
- Communities are private by default.
- Joining is invite code/link only.
- A user can belong to multiple communities.
- Feed content is visible only to members of the relevant community.

### Logging and media
- Every game log requires at least one photo.
- Logger manually selects winners, losers, and participants from profiles within selected community.
- Only log creator can edit/delete a game log.

### Competition model
- Bracket participants auto-include all community members.
- Bracket creator selects seeding method: by odds, manual, or random.
- If seeding by odds and community data is sparse, use `overallOdds` as fallback.
- All members have equal permissions in V1 (no roles).

### Odds logic
- V1 odds are based on simple win rate.
- `overallOdds`: based on all games across communities.
- `communityOdds`: based only on games in that community.
- Pong cups-hit stats are recorded and displayed, but do not auto-decide winner.

## Core features

1. **Home feed as default landing screen**
   - Shows recent logs from the user's communities
   - should be able to filter based on what communities the user is in
   - Primary actions: `Profile`, `Communities`, `Log New Game`

2. **Private communities**
   - Create community
   - Invite members with code/link
   - View community roster and shared activity

3. **Game logging**
   - Select community and game type
   - Add participants plus manual winners and losers
   - Upload required photo(s)
   - Add game-specific stats (Pong cups-hit in V1)

4. **Odds and profiles**
   - User profile shows identity plus aggregate stats
   - user profile private view shows all logged games they are a part of
   - Community views show member-specific community odds

5. **Brackets**
   - Standard tournament bracket object
   - Auto-populated participants from community
   - User-selectable seeding: odds, manual, or random

## Core components

### Profile object
- `id` (UUID)
- `googleAuthId` (string)
- `displayName` (string)
- `profilePhotoUrl` (string, nullable)
- `overallOdds` (computed decimal)
- `createdAt` / `updatedAt`

### Community object
- `id` (UUID)
- `name` (string)
- `createdByProfileId` (UUID)
- `inviteCode` (string, unique)
- `inviteLink` (string)
- `createdAt` / `updatedAt`

### CommunityMembership object
- `communityId` (UUID)
- `profileId` (UUID)
- `joinedAt` (timestamp)
- `communityOdds` (computed decimal; can be materialized/cached)

### GameLog object
- `id` (UUID)
- `communityId` (UUID)
- `gameType` (enum: `PONG`, `BEER_BALL`, `BATTLE_PONG`, `BASEBALL`)
- `createdByProfileId` (UUID)
- `participantProfileIds` (array<UUID>)
- `winnerProfileIds` (array<UUID>, min length 1)
- `loserProfileIds` (array<UUID>, min length 1)
- `photoUrls` (array<string>, min length 1)
- `notes` (string, optional)
- `createdAt` / `updatedAt`

### PongStats object (child of GameLog)
- `gameLogId` (UUID)
- `playerCupsHit` (map/profileId -> integer)

### Bracket object
- `id` (UUID)
- `communityId` (UUID)
- `participantProfileIds` (array<UUID>, auto all members)
- `seedMethod` (enum: `COMMUNITY_ODDS`, `MANUAL`, `RANDOM`)
- `rounds` (structured rounds/matches)
- `status` (`DRAFT`, `ACTIVE`, `COMPLETE`)
- `createdAt` / `updatedAt`

### Derived calculations
- `overallOdds(profileId) = totalWins / totalGames`
- `communityOdds(profileId, communityId) = communityWins / communityGames`
- For display, clamp to precision (e.g., 2-3 decimals) consistently.

## App/user flow

### 1) Onboarding flow
1. Open app
2. Continue with Google
3. If first login, accept self-confirmation `I am 21+`
4. If first login or missing required profile fields, set display name and profile photo
5. Enter home feed

### Returning user shortcut flow
1. Open app
2. Continue with saved/active session (or quick Google re-auth)
3. If onboardingComplete is true, route directly to home feed

### 2) Home feed flow
1. User lands on feed after login
2. Feed queries recent logs from all communities user belongs to
3. User can tap:
   - `Profile`
   - `Communities`
   - `Log New Game`

### 3) Community flow
1. User opens communities
2. User can create a new community
3. User can join an existing community via invite code/link
4. Community detail shows members, logs, and bracket context

### 4) Log new game flow
1. Tap `Log New Game`
2. Select target community
3. Select game type
4. Select participants
5. Enter stats (Pong: cups-hit per player through playful/tappable UI)
6. Select winners and losers manually
7. Upload at least one photo
8. Submit log
9. System recalculates odds and updates feed items

### 5) Bracket flow
1. User opens bracket in a community
2. Bracket participant list auto-loads all members
3. Seeds assigned by selected seeding method (odds/manual/random)
4. Match outcomes update bracket progression
5. Completed bracket view persists in community history

## Techstack

### Recommended V1 stack
- **Client:** Swift + SwiftUI (iOS-first)
- **Authentication:** Firebase Authentication with Google Sign-In provider
- **Backend platform:** Firebase + Google Cloud
- **Database:** Cloud Firestore
- **Storage:** Firebase Storage for profile and log photos
- **Server logic:** Cloud Functions for Firebase (odds recalculation, bracket utilities)
- **Analytics/crash:** Firebase Analytics + Crashlytics

### Why this stack
- Speeds up V1 delivery with managed auth, data, and storage.
- Works well for mobile-first, event-driven app workflows with strong Google ecosystem integration.
- Keeps architecture simple while remaining extensible for future game logic.

## Implementation plan

### Phase 0 - Product and schema lock
- Finalize object schemas and field constraints.
- Define API contracts for auth, communities, logs, odds, and brackets.
- Confirm copy/legal text for 21+ self-confirmation.

### Phase 1 - Foundation
- Implement Google auth and onboarding.
- Persist onboarding state flags (`ageConfirmed21PlusAt`, `onboardingCompleteAt`).
- Create profile management (display name, photo).
- Build app shell with feed-centered navigation.

### Phase 2 - Communities and access
- Implement create/join (invite-only) community flows.
- Enforce membership checks on reads/writes.
- Implement private feed query by memberships.

### Phase 3 - Logging system (Pong-first)
- Build game log creation with required photos.
- Implement manual winners/losers selection.
- Implement Pong cups-hit input UI and storage.
- Add edit/delete restrictions to log creator only.

### Phase 4 - Odds engine and profiles
- Implement win-rate calculators for overall and per-community views.
- Recompute stats on create/update/delete of logs.
- Surface odds in profile and community member lists.

### Phase 5 - Brackets
- Implement bracket data model and rendering.
- Auto-include all community members as participants.
- Support odds/manual/random seeding workflows.
- Support match updates and completion states.

### Phase 6 - QA and launch readiness
- Validate privacy boundaries between communities.
- Test image upload reliability and required-photo enforcement.
- Test odds correctness and edge cases (small sample sizes, ties in win rate).
- Add instrumentation and crash monitoring.

## Functional requirements by screen

### Feed screen
- Show chronological game logs from user's communities.
- Include essential metadata: community, game type, winners/losers, photo preview, timestamp.
- Include direct access to Profile, Communities, and Log New Game.

### Profile screen
- Edit display name and profile photo.
- Show overall odds and summary stats.
- Optional: recent games logged by this user.

### Communities screen
- List joined communities.
- Create new community.
- Join with invite code/link.

### Community detail screen
- Display member list.
- Display community-specific feed subset.
- Display bracket summary and entry point.

### New log screen
- Required fields: community, game type, participants, winners, losers, photo(s).
- Game-type specific fields:
  - Pong: cups-hit per player
  - Others: basic placeholders until rule specs are finalized

### Bracket screen
- Show seeded tournament bracket.
- Show current round and results.
- Persist completed bracket history.

## Permissions and privacy

- All communities are private.
- User can only read/write data for communities they belong to.
- Logs are visible only to members of the same community.
- Only log creator can edit/delete their log.
- No special admin/mod roles in V1.

## Edge cases and handling

- User belongs to zero communities: show CTA to create or join.
- Invite code invalid/expired: show clear retry state.
- Any winner/loser selected but not in participants: block submit.
- Same profile present in both winners and losers: block submit.
- Photo upload fails: keep draft and allow retry.
- Same user in multiple communities with different odds: always scope correctly.
- Win-rate ties for odds-based seeding: deterministic secondary sort (e.g., profile creation date or UUID).

## Future scope (post-V1)

- Detailed rules engines for Beer Ball, Battle Pong, and Baseball.
- Role model (admin/mod/member) if governance needs grow.
- Moderation/reporting for photo/content abuse.
- Richer ranking formulas (ELO, recency weighting).
- Public/private community modes and discovery.

## Open items for next requirement round

1. Detailed scoring/rules for `Beer Ball`, `Battle Pong`, `Baseball`
2. Bracket creation cadence constraints (if any) per community
3. Moderation/reporting requirements for user photos
4. Legal/compliance review depth for alcohol-related social app positioning
