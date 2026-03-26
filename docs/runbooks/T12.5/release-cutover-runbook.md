# T12.5 Release Cutover Runbook (Pre-Connect + Post-Connect)

## Purpose
Provide a deterministic, low-risk path to:
- Prepare production Firebase release inputs before App Store Connect is ready.
- Execute production deployment and release tagging once Connect readiness is confirmed.

## Environment aliases (guardrail)
Use the aliases defined in `.firebaserc`:
- `default` -> `bitchcup-dev`
- `dev` -> `bitchcup-dev`
- `prod` -> `bitchcup-prod`

Always run production commands with explicit `--project bitchcup-prod` (or `--project prod`) and `--config ./firebase.json`.

## A) Pre-Connect checklist (execute now)

### A1) Pre-command verification
Run from repo root:

```bash
firebase projects:list
firebase use
git rev-parse --short HEAD
git status --short
```

Expected:
- Firebase CLI is authenticated.
- Active default is dev (safety).
- Release candidate SHA is known.
- Working tree is clean or intentionally documented.

### A2) Deterministic production command set (prepared, not executed until Connect gate)
Run from repo root when authorized for production cutover:

```bash
# Firestore rules
firebase --config ./firebase.json --project bitchcup-prod deploy --only firestore:rules

# Firestore indexes
firebase --config ./firebase.json --project bitchcup-prod deploy --only firestore:indexes

# Storage rules
firebase --config ./firebase.json --project bitchcup-prod deploy --only storage:rules

# Cloud Functions
firebase --config ./firebase.json --project bitchcup-prod deploy --only functions
```

### A3) Release tag convention and annotation template
Tag naming:
- Release candidate: `vMAJOR.MINOR.PATCH-rcN` (optional)
- Final release: `vMAJOR.MINOR.PATCH`

Annotated tag template:

```text
Release: vMAJOR.MINOR.PATCH
Date: YYYY-MM-DD HH:MM TZ
Commit: <full_sha>
Firebase project: bitchcup-prod
Deploy scope: firestore.rules, firestore.indexes, storage.rules, functions
Smoke checks: pass/fail + notes
Rollback target: <last-known-good tag>
```

Command template:

```bash
git tag -a vMAJOR.MINOR.PATCH -m "$(cat <<'EOF'
Release: vMAJOR.MINOR.PATCH
Date: YYYY-MM-DD HH:MM TZ
Commit: <full_sha>
Firebase project: bitchcup-prod
Deploy scope: firestore.rules, firestore.indexes, storage.rules, functions
Smoke checks: pass/fail + notes
Rollback target: <last-known-good tag>
EOF
)"
```

### A4) Preflight production safety review
Verify production-bound deploy assets and assumptions:

- `firebase.json`
  - `firestore.rules` -> `firebase/firestore.rules`
  - `firestore.indexes` -> `firebase/firestore.indexes.json`
  - `storage.rules` -> `firebase/storage.rules`
  - `functions.source` -> `functions`
- `firebase/firestore.rules`
  - Deny-by-default pattern exists.
  - Community/member and ownership constraints are present.
- `firebase/firestore.indexes.json`
  - Indexes align with current feed/membership/log queries.
- `firebase/storage.rules`
  - Auth required, membership checks enforced for community media, owner-only writes/deletes.
- `functions/package.json`
  - Node runtime is `20`.
  - Build/lint/test scripts present for release verification.

Required preflight signoff:
- No debug-only bypasses for production authorization paths.
- No pending security-rule changes left untested.
- No unresolved release-blocking defects tracked as P0/P1.

## B) Connect readiness gate (must be true before production cutover)
Treat gate as satisfied only when all are true:
1. App Store Connect version/build status is ready for launch path.
2. Release candidate commit SHA is frozen.
3. Release owner approves production cutover window.

If any condition fails, do not run production deploy or create final tag.

## C) Post-Connect execution sequence (exact steps)
Run in order:

1. **Freeze release SHA**
   - Record full SHA and confirm no new commits are being included.
2. **Verify production target**
   - `firebase use`
   - Confirm command invocations still include explicit `--project bitchcup-prod`.
3. **Deploy production Firebase configuration**
   - Deploy in this order:
     1) `firestore:rules`
     2) `firestore:indexes`
     3) `storage:rules`
     4) `functions`
4. **Run production smoke checks**
   - Auth sign-in.
   - Community-scoped read.
   - Game log create with required photo.
   - Feed read.
   - Bracket-linked game log path (if bracket is active in release scope).
5. **Create final annotated release tag**
   - Create tag from deployed SHA using template above.
6. **Start T12.6 monitoring**
   - Monitor first 72 hours for crashes, auth issues, and rule denials.
   - Trigger T12.4 incident/rollback runbooks if thresholds are exceeded.

## D) Evidence to capture in release notes
- Deployed SHA
- Timestamp per deploy step
- Smoke test outcomes
- Final tag created
- Owner on call for first 72 hours
