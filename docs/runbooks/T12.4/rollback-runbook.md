# T12.4 Rollback Runbook (Last Known Good -> Production)

## Goal
Restore production to the last-known-good state with minimal further user impact.

## Inputs required (before you roll anything back)
Fill these placeholders:
- LKG (last-known-good) identifier:
  - Git tag/commit: `T12.5 LKG tag: ____`
  - iOS build version: `____`
  - Backend deploy timestamps: `____`
- Production Firebase project id (as used by your CLI):
  - `bitchcup-prod` (preferred, confirm exact string)

## Component rollback matrix
1. iOS crash or app logic regression
   - Rollback by distributing a previous iOS build (App Store Connect / TestFlight)
2. Firestore security rule failures
   - Rollback by redeploying last-known-good:
     - `firestore:rules`
     - `firestore:indexes` (only if the incident is due to missing/changed indexes)
3. Storage upload/download failures
   - Rollback by redeploying last-known-good `storage:rules`
4. Cloud Functions derived-field bugs (odds + bracket sync)
   - Rollback by redeploying last-known-good Functions code
   - Decide whether optional backfill is required (see below)

## Backend rollback commands (Firebase)
Run from repo root where possible.

### 1) Firestore rules rollback (SEV-1/2 rule denials)
```bash
firebase --config ./firebase.json --project bitchcup-prod deploy --only firestore:rules
```

### 2) Storage rules rollback (SEV-1 upload/download issues)
```bash
firebase --config ./firebase.json --project bitchcup-prod deploy --only storage:rules
```

### 3) Firestore index rollback (only if you see index errors)
```bash
firebase --config ./firebase.json --project bitchcup-prod deploy --only firestore:indexes
```

### 4) Cloud Functions rollback (odds/bracket triggers/callables)
From repo root:
```bash
cd functions
firebase --config ../firebase.json --project bitchcup-prod deploy --only functions
```
If you need to run the same via your npm script (not project-scoped), prefer explicit `firebase ... --project ...` like above for correctness.

## iOS rollback steps (App Store Connect)
Because iOS rollback requires a build upload, use the “stop bad release -> distribute LKG build” sequence:

1. If the release is in TestFlight only:
   - Pause/stop distribution of the bad TestFlight build (release management UI)
2. If the release is already live on the App Store:
   - Remove the current version from sale (or stop rollout, depending on App Store Connect controls)
3. Upload LKG IPA (or re-upload the last known good build artifacts)
4. Create a new release (TestFlight first; production after quick smoke validation)

## Optional backfill / recovery (only if user impact persists after rollback)
Rollback fixes future event handling; it may not repair already-wrong derived fields.

### A) Odds derived fields (`profiles.overallOdds`, `memberships.communityOdds`)
If odds are incorrect due to Functions logic:
- After rollback, wait for normal gameplay to trigger recomputation on new/updated `gameLogs`.
- If you must repair existing data, options:
  - One-off admin script/function that rewrites impacted `gameLogs` to retrigger `onDocumentCreated/Updated` triggers in `functions/src/gameLogTriggers.ts`.
  - Alternatively, update an innocuous field on each impacted `gameLogs` document (requires careful coordination to avoid expensive scans).

### B) Bracket progression bugs
Bracket progression is driven primarily by game log events:
- `applyBracketOutcomeFromGameLogCreate` runs on `gameLogs/{gameLogId}` document creation.

If the wrong bracket progression was written by bad Functions logic:
- Redeploy the previous Functions build to fix future progression.
- If existing brackets are corrupted, recovery generally requires a targeted backfill:
  - Reprocess affected brackets by iterating impacted `gameLogs` and reapplying outcomes server-side
  - (Best practice: create a temporary one-off Cloud Function that calls the pure core logic from `bracketGameLogSync.ts` / related helpers)

## Validation after rollback (minimum)
Run quick production-safety checks:
- Crashlytics: crash-free sessions returns to baseline for the rolled-back timeframe
- Firestore: confirm rule denials stop (on onboarding + feed read + log create)
- One happy path per critical flow:
  - Sign in (Google)
  - Complete 21+ onboarding gate
  - Create a game log with required photo evidence
  - Verify feed card appears
  - If brackets impacted: verify at least one bracket progression step

## Rollback checklist (printable)
- [ ] LKG version/tag/commit identified
- [ ] Severity confirmed and rollback scope chosen
- [ ] Backend rollback commands executed (if backend is implicated)
- [ ] iOS rollback build distributed (if iOS is implicated)
- [ ] Evidence captured (before/after metrics)
- [ ] Validation completed
- [ ] Incident status updated + postmortem scheduled

