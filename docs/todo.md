# Two-Developer Build Plan (From PRD)

This plan is sequenced to let two developers work in parallel with clear handoff points and no orphan tasks.

## Task Dependency Map (High Level)

- `T01 -> T02 -> (T03, T04) -> (T05, T06) -> (T07, T08) -> T09 -> T10 -> T11 -> T12`
- `T04` and `T05` can overlap after shared contracts are defined.
- `T07` depends on both `T05` and `T06`.

## Tasks and Subtasks

### [ ] T01. Project Setup and Team Operating System

**Depends on:** `[]`

- `T01.1` Create repo structure (`ios/`, `functions/`, `docs/`) with README and contribution guide.
- `T01.2` Define branching strategy, PR template, review checklist, and commit conventions.
- `T01.3` Set up CI for iOS build and Cloud Functions lint/test.
- `T01.4` Create Firebase projects (`dev`, `prod`) and grant team access.
- `T01.5` Set up project board states (`Backlog`, `In Progress`, `Review`, `QA`, `Done`) and map task IDs.

### [ ] T02. Architecture, Contracts, and Data Model Freeze

**Depends on:** `[T01]`

**Reference docs:**
- `docs/architecture/data-model.md`
- `docs/architecture/data-contracts.md`
- `docs/architecture/api-contracts.md`

- `T02.1` Finalize Firestore collection/document shapes for `profiles`, `communities`, `memberships`, `gameLogs`, and `brackets`.
- `T02.2` Define enums/constants for game types and seeding methods (`COMMUNITY_ODDS`, `MANUAL`, `RANDOM`).
- `T02.3` Define Cloud Functions API contracts (request/response/error format).
- `T02.4` Define odds computation contract (`overallOdds`, `communityOdds`) and tie-break behavior.
- `T02.5` Define onboarding flags (`ageConfirmed21PlusAt`, `onboardingCompleteAt`).
- `T02.6` Write acceptance criteria per feature and testing checklist.

### [ ] T03. Firebase Foundation and Security Rules

**Depends on:** `[T02]`

- `T03.1` Configure Firebase Auth with Google provider.
- `T03.2` Create baseline Firestore indexes for feed, memberships, and logs.
- `T03.3` Configure Firebase Storage buckets/folders for profile and game photos.
- `T03.4` Write Firestore security rules for:
  - `T03.4.a` Community-only read/write access
  - `T03.4.b` Creator-only game log edit/delete
  - `T03.4.c` Membership checks for all community data
- `T03.5` Write Storage rules aligned with membership and ownership.
- `T03.6` Add Firebase emulator config and local dev scripts.

### [ ] T04. iOS App Skeleton and Navigation

**Depends on:** `[T02]`

- `T04.1` Initialize SwiftUI app architecture with feature modules and shared services.
- `T04.2` Build root routing (`Onboarding` vs `HomeFeed`).
- `T04.3` Implement primary navigation paths (`Profile`, `Communities`, `Log New Game`).
- `T04.4` Add session/app state manager and dependency injection setup.
- `T04.5` Add shared loading, empty, and error UI states.

### [ ] T05. Authentication and One-Time Onboarding

**Depends on:** `[T03, T04]`

- [x] `T05.1` Integrate Google Sign-In using Firebase Auth.
- [x] `T05.2` Implement first-login 21+ confirmation step.
- [x] `T05.3` Build profile setup for display name and profile photo upload.
- [x] `T05.4` Persist onboarding state and route returning users directly to home feed.
- [x] `T05.5` Add guardrails for incomplete onboarding states.
- [x] `T05.6` Add analytics events for onboarding funnel steps.

### [ ] T06. Communities (Create, Invite-Only Join, Membership)

**Depends on:** `[T03, T04]`

- `T06.1` Implement create-community flow with invite code/link generation.
- `T06.2` Implement join-by-invite code/link validation and membership creation.
- `T06.3` Prevent duplicate memberships and invalid join attempts.
- `T06.4` Build communities list and community detail shell views.
- `T06.5` Implement member roster rendering.
- `T06.6` Add empty/error states for no communities and invalid/expired invite links.

### [ ] T07. Game Logging (Pong-First, Multi-Winner/Loser, Required Photos)

**Depends on:** `[T05, T06]`

- `T07.1` Build new-log form (community, game type, participants).
- `T07.2` Add multi-select winners and losers with validation:
  - `T07.2.a` Winners/losers must be selected from participants
  - `T07.2.b` Same profile cannot be in both winners and losers
- `T07.3` Enforce at least one photo before submit.
- `T07.4` Build Pong cups-hit input UI per player.
- `T07.5` Add basic stat placeholders for Beer Ball, Battle Pong, and Baseball.
- `T07.6` Implement creator-only edit/delete enforcement.
- `T07.7` Add retry and validation UX for submission failures.

### [ ] T08. Feed and Profile Stats Surfaces

**Depends on:** `[T05, T06, T07]`

- `T08.1` Implement home feed query scoped to user communities only.
- `T08.2` Render feed cards with game type, winners/losers, photo preview, and timestamp.
- `T08.3` Add community filter controls on feed.
- `T08.4` Build profile private view with user game history and aggregate stats.
- `T08.5` Build community detail feed subset.
- `T08.6` Add pagination and empty states.

### [ ] T09. Odds Engine (Overall and Community)

**Depends on:** `[T07, T08]`

- `T09.1` Implement Cloud Functions triggers for game log create/update/delete.
- `T09.2` Compute and persist `overallOdds` per profile.
- `T09.3` Compute and persist `communityOdds` per profile per community.
- `T09.4` Add sparse-data fallback behavior where applicable.
- `T09.5` Implement deterministic tie-break helper for odds-based seeding.
- `T09.6` Wire odds display into profile and community member views.

### [ ] T10. Brackets (Auto Participants plus Selectable Seeding)

**Depends on:** `[T06, T09]`

- `T10.1` Implement bracket model for rounds, matches, and status.
- `T10.2` Auto-populate bracket participants from all community members.
- `T10.3` Implement seeding selector (`odds`, `manual`, `random`).
- `T10.4` Implement odds seeding with fallback and tie-break behavior.
- `T10.5` Implement manual seeding UI with validation.
- `T10.6` Implement random seeding using deterministic seed strategy.
- `T10.7` Build bracket visualization and match result updates.

### [ ] T11. Quality, Security, and Observability

**Depends on:** `[T08, T09, T10]`

- `T11.1` Add unit tests for odds and seeding logic.
- `T11.2` Add integration tests for Firestore/Storage security rules.
- `T11.3` Add UI tests for onboarding, game logging, and bracket critical paths.
- `T11.4` Add Firebase Analytics and Crashlytics instrumentation to major flows.
- `T11.5` Run performance pass (indexes, query costs, payload size).
- `T11.6` Run lightweight threat modeling for unauthorized access and abuse risks.

### [ ] T12. Release Preparation and Launch

**Depends on:** `[T11]`

- `T12.1` Execute UAT in `dev` against acceptance criteria.
- `T12.2` Fix launch-blocking defects and rerun regression suite.
- `T12.3` Finalize App Store metadata and policy wording for alcohol context.
- `T12.4` Create incident response and rollback runbooks.
- `T12.5` Deploy production Firebase configuration and create release tag.
- `T12.6` Monitor first 72 hours for crashes, auth issues, and rule denials.

## Parallel Work Allocation

- **Developer A lane:** `T04 -> T05 -> T07 -> T08 -> T10 (UI) -> T11 -> T12`
- **Developer B lane:** `T03 -> T06 -> T07 (validation/backend) -> T09 -> T10 (engine) -> T11 -> T12`

## Shared Checkpoints

- `C01` After `T02`: architecture/contracts signoff
- `C02` Mid `T07`: payload and validation parity check
- `C03` Start `T10`: seeding UX and backend alignment
- `C04` Pre `T12`: release readiness signoff

