# bcup Acceptance Criteria and Testing Checklist

This document defines V1 acceptance criteria per feature and the minimum testing checklist for development and release readiness.

## Feature acceptance criteria

### 1) Authentication and onboarding

- [ ] User can sign in with Google successfully.
- [ ] First successful login requires 21+ confirmation.
- [ ] User can set `displayName` during onboarding.
- [ ] If profile photo is required by current UX decision, user can set `profilePhotoUrl` during onboarding.
- [ ] `ageConfirmed21PlusAt` and `onboardingCompleteAt` persist to `profiles`.
- [ ] Returning users with non-null `onboardingCompleteAt` route directly to feed.

### 2) Communities (create and join)

- [ ] Authenticated user can create a private community.
- [ ] Community has valid `inviteCode` and `inviteLink`.
- [ ] User can join with a valid invite code/link.
- [ ] Duplicate membership creation is blocked.
- [ ] Invalid or expired invite flow returns a clear retryable error state.
- [ ] Community member roster renders all members accurately.

### 3) Game logging

- [ ] User can create a game log with required fields.
- [ ] Submission is blocked unless at least one photo is attached.
- [ ] Winners and losers must be selected from participants.
- [ ] Same profile cannot appear in both winners and losers.
- [ ] Only log creator can edit their game log.
- [ ] Only log creator can delete their game log.
- [ ] Failed submissions preserve form state and allow retry.

### 4) Feed and profile stats surfaces

- [ ] Home feed includes only logs from communities the user belongs to.
- [ ] Feed cards render community, game type, winners/losers, photo preview, and timestamp.
- [ ] Community filter updates feed results correctly.
- [ ] Profile private view displays user game history and aggregate stats.
- [ ] Empty states appear for no communities and no logs.

### 5) Odds engine

- [ ] Game log create/update/delete triggers odds recomputation.
- [ ] `profiles.overallOdds` updates according to the odds contract.
- [ ] `memberships.communityOdds` updates according to the odds contract.
- [ ] Zero-game fallback behavior matches contract.
- [ ] Tie-break order is deterministic and consistent across re-runs.

### 6) Brackets

- [ ] Bracket participant list auto-populates from community members.
- [ ] Seeding method selection supports `COMMUNITY_ODDS`, `MANUAL`, and `RANDOM`.
- [ ] Odds seeding uses contract fallback and deterministic tie-break order.
- [ ] Match result updates advance bracket state correctly.
- [ ] Completed bracket state persists for later viewing.

### 7) Security and privacy

- [ ] Non-members cannot read community-scoped data.
- [ ] Members only access communities they belong to.
- [ ] Creator-only edit/delete enforcement is effective for game logs.
- [ ] Server-owned derived fields are not client-writable.

## Testing checklist

### A) Data and API contract tests

- [ ] Firestore documents conform to `docs/architecture/data-contracts.md` required fields, types, and defaults.
- [ ] API request/response/error shapes conform to `docs/architecture/api-contracts.md`.
- [ ] Enum values are validated and rejected when invalid.

### B) Firestore rules tests

- [ ] Own profile read/write allowed; other profile access denied.
- [ ] Non-member cannot read community, game log, or bracket data.
- [ ] Member can read data for their communities only.
- [ ] Non-creator cannot update/delete another user's game log.
- [ ] Membership ID and ownership constraints are enforced.

### C) Functional end-to-end tests

- [ ] New user onboarding path (sign in -> 21+ confirm -> profile setup -> feed) works.
- [ ] Returning user path bypasses onboarding when complete.
- [ ] Create and join community flows work end-to-end.
- [ ] Create/update/delete game log flows work end-to-end.
- [ ] Bracket creation and match update flows work end-to-end.

### D) Odds correctness tests

- [ ] Win-rate calculations are correct for standard scenarios.
- [ ] Zero denominator scenarios resolve to configured fallback.
- [ ] Update/delete of historical logs recalculates dependent odds correctly.
- [ ] Tie cases produce stable ordering using contract tie-break sequence.

### E) Reliability and UX checks

- [ ] Upload failure paths provide clear messaging and retry action.
- [ ] Network/API errors produce user-safe error states.
- [ ] Core queries run without missing index errors.
- [ ] Critical happy paths run without crashes in iOS simulator.

### F) Release readiness checks (`dev` -> `prod`)

- [ ] CI passes (iOS build plus Cloud Functions lint/test).
- [ ] Smoke tests pass in `dev`.
- [ ] Production deploy completes successfully.
- [ ] Post-deploy smoke checks pass: auth, communities, game log create, feed read.

## Exit criteria for T02.6

- [ ] All feature acceptance criteria are reviewed and agreed by both developers.
- [ ] Testing checklist is linked in PR descriptions for relevant features.
- [ ] Any unmet criteria are explicitly tracked with task IDs before release.
