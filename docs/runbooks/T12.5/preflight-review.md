# T12.5 Preflight Review (Production Firebase Safety)

## Scope
Review production-bound Firebase deploy assets and Functions runtime settings before App Store Connect cutover.

## Reviewed artifacts
- `firebase.json`
- `firebase/firestore.rules`
- `firebase/firestore.indexes.json`
- `firebase/storage.rules`
- `functions/package.json`
- `.firebaserc`

## Results

### 1) Firebase config wiring
- Status: PASS
- Notes:
  - Firestore rules path is `firebase/firestore.rules`.
  - Firestore indexes path is `firebase/firestore.indexes.json`.
  - Storage rules path is `firebase/storage.rules`.
  - Functions source is `functions`.

### 2) Firestore rules safety posture
- Status: PASS
- Notes:
  - Rules use membership and ownership checks on community-scoped writes.
  - Deny-by-default fallback is present.

### 3) Storage rules safety posture
- Status: PASS
- Notes:
  - Auth required for reads on profile photos.
  - Community membership required for game photo reads.
  - Uploader ownership checks enforce create/update/delete permissions.
  - File type and size constraints exist for image uploads.

### 4) Firestore indexes readiness
- Status: PASS (structure reviewed)
- Notes:
  - Index manifest is present and correctly referenced.
  - Final runtime validation still required during prod smoke checks.

### 5) Functions runtime/build guardrails
- Status: PASS
- Notes:
  - `engines.node` is set to `20`.
  - `lint`, `typecheck`, `test`, and `build` scripts are defined.

### 6) Environment alias guardrails
- Status: PASS
- Notes:
  - `.firebaserc` now defines `dev` and `prod` aliases.
  - `default` remains mapped to dev for safety.

## Open checks at cutover time (post-Connect)
- Re-verify release SHA freeze.
- Re-run smoke checks in production after deploy.
- Confirm no new P0/P1 defects were introduced between preflight and cutover.

## Signoff template
- Reviewer:
- Date:
- Release SHA:
- Decision: Go / No-go
