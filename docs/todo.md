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

- `T05.1` Integrate Google Sign-In using Firebase Auth.
- `T05.2` Implement first-login 21+ confirmation step.
- `T05.3` Build profile setup for display name and profile photo upload.
- `T05.4` Persist onboarding state and route returning users directly to home feed.
- `T05.5` Add guardrails for incomplete onboarding states.
- `T05.6` Add analytics events for onboarding funnel steps.

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
- `T07.5` Add basic stat placeholders for Pong, Beer Ball, Battle Pong, and Baseball.
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
- [x] `T10.5` Implement manual team assignment UI with validation.
- [x] `T10.6` Implement random seeding using deterministic seed strategy.
- `T10.7` Build bracket visualization and match result updates.
  - **Option 2 (chosen):** Bracket outcomes come from the normal **game log** flow. Optional `bracketId` + `bracketMatchId` on `gameLogs`; `gameLog` create still drives community/overall odds via existing triggers; a Cloud Function applies the same outcome to the bracket document.
  - `T10.7.a` **Contracts:** Add optional `bracketId` and `bracketMatchId` to `gameLogs` in `data-contracts.md` and `data-model.md`; document behavior in `api-contracts.md` (callable `updateMatchResult` is non-primary / optional for backfill).
  - `T10.7.b` **Rules:** Extend `hasGameLogKeys()` in `firestore.rules` so client creates may include those optional fields.
  - `T10.7.c` **Functions:** On `gameLogs` **create**, when both bracket fields are set: load bracket, find `matchId`, validate community + roster + no prior outcome; write `winnerProfileIds` / `loserProfileIds` on the match; advance winners through `feederMatchIds` into the next match’s `participantProfileIds`; idempotent skip if match already has outcome; set bracket `COMPLETE` when the final is decided (define edge cases for byes / placeholders).
  - `T10.7.d` **iOS:** Extend `GameLogCreatePayload` and `createGameLog` to pass optional bracket fields; prefill `NewGameLogFormView` from a bracket match (community, participants, `teamSize`); add “Log result” (or equivalent) from bracket UI into that flow.

### [ ] T11. Quality, Security, and Observability

**Depends on:** `[T08, T09, T10]`

- [x] `T11.1` Add unit tests for odds and seeding logic.
- [x] `T11.2` Add integration tests for Firestore/Storage security rules.
- `T11.3` Add UI tests for onboarding, game logging, and bracket critical paths.
- [x] `T11.4` Add Firebase Analytics and Crashlytics instrumentation to major flows.
- [x] `T11.5` Run performance pass (indexes, query costs, payload size).
- [x] `T11.6` Run lightweight threat modeling for unauthorized access and abuse risks.

### [ ] T12. Release Preparation and Launch

**Depends on:** `[T11]`

- `T12.1` Execute UAT in `dev` against acceptance criteria.
  - Handoff note: UAT execution record is prepared at `docs/uat/dev-uat-t12.1.md`.
  - Current state: setup/template complete; full checklist execution is still pending.
  - Known blocker: embedded terminal instability for long `xcodebuild test` runs.
  - Resume command (run from macOS Terminal, repo root):
    - `xcodebuild test -project ios/bitchcup/bitchcup.xcodeproj -scheme bitchcup -destination "platform=iOS Simulator,id=99FC3826-FEA5-4BAB-B272-AAA8AC29E6D2" -only-testing:bitchcupUITests`
- `T12.2` Fix launch-blocking defects and rerun regression suite.
- `T12.3` Finalize App Store metadata and policy wording for alcohol context.
- `T12.4` Create incident response and rollback runbooks.
- `T12.5` Deploy production Firebase configuration and create release tag.
  - Pre-Connect prep runbook: `docs/runbooks/T12.5/release-cutover-runbook.md`.
  - App Store Connect gate (must be true before prod cutover): release build/status ready, release SHA frozen, release owner approval captured.
  - Once Connect is set, execute in order:
    - Freeze release SHA and verify explicit prod target (`bitchcup-prod`) for all Firebase commands.
    - Deploy: `firestore:rules` -> `firestore:indexes` -> `storage:rules` -> `functions`.
    - Run prod smoke checks (auth, community read, game log + photo, feed read, bracket-linked path where applicable).
    - Create annotated final release tag from deployed SHA.
    - Start T12.6 72-hour monitoring window.
- `T12.6` Monitor first 72 hours for crashes, auth issues, and rule denials.

## Parallel Work Allocation

- **Developer A lane:** `T04 -> T05 -> T07 -> T08 -> T10 (UI) -> T11 -> T12`
- **Developer B lane:** `T03 -> T06 -> T07 (validation/backend) -> T09 -> T10 (engine) -> T11 -> T12`

## Shared Checkpoints

- `C01` After `T02`: architecture/contracts signoff
- `C02` Mid `T07`: payload and validation parity check
- `C03` Start `T10`: seeding UX and backend alignment
- `C04` Pre `T12`: release readiness signoff

## Add-on Reliability Track (Photo Caching)

### [ ] T13. Feed Photo Caching and Reliability Hardening

**Depends on:** `[T07, T08]`

- `T13.1` Add image-load baseline metrics for feed cards:
  - `T13.1.a` Track first-load success, first-load failure, retry success, and final failure.
  - `T13.1.b` Record median time-to-visible image in feed sessions.
- `T13.2` Implement image CDN/transformation path (Cloudinary/imgix/Firebase Resize Images):
  - `T13.2.a` Define transformed URL contract for feed thumbnails (for example `w=400,h=400`).
  - `T13.2.b` Enable automatic modern format delivery (WebP/HEIF where supported).
  - `T13.2.c` Enable auto-quality tuning based on client/network conditions.
  - `T13.2.d` Keep original images as source of truth; serve transformed variants in feed/profile/community UIs.
- `T13.3` Add client-side upload preprocessing on iOS:
  - `T13.3.a` Downscale photos before upload to a max dimension target (for example 1080px width).
  - `T13.3.b` Apply JPEG compression target before `putData` (baseline quality ~`0.7`, tune via QA).
  - `T13.3.c` Validate visual quality and upload speed tradeoff on recent and older iPhone devices.
- `T13.4` Upgrade client image pipeline and caching strategy:
  - `T13.4.a` Evaluate and select `Kingfisher` or `SDWebImage` for feed/profile/community images.
  - `T13.4.b` Configure memory and disk cache limits with eviction policy.
  - `T13.4.c` Add scroll prefetch for next 5-10 feed cells.
  - `T13.4.d` Preserve retry behavior for transient failures and explicit `tap to retry` fallback.
- `T13.5` Apply cost mitigation controls:
  - `T13.5.a` Set strong `Cache-Control` metadata on Storage objects (game photos and profile photos).
  - `T13.5.b` Evaluate Firebase Hosting-in-front-of-Storage as CDN layer and document cost impact.
  - `T13.5.c` Add lifecycle policy for temporary/ephemeral media where product rules allow deletion.
- `T13.6` Improve perceived speed UX:
  - `T13.6.a` Add BlurHash or ThumbHash placeholder string to image metadata.
  - `T13.6.b` Render instant blurred placeholder while full image loads.
  - `T13.6.c` Add progressive loading path (low-quality preview -> final quality swap).
- `T13.7` Run validation pass on constrained network:
  - `T13.7.a` Verify reduced sticky `Photo unavailable` incidents without manual refresh.
  - `T13.7.b` Compare before/after metrics and summarize bandwidth impact.
  - `T13.7.c` Report Firebase Storage egress trend change after rollout.

