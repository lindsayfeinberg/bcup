# Cloud Functions Setup (`functions/`)

This guide explains how to develop, test, and deploy Firebase Cloud Functions for `bcup`.

## Prerequisites

- Node.js 20.x
- npm 10+
- Firebase CLI (`npm i -g firebase-tools`)
- Access to Firebase projects (`dev`, `prod`)

Verify:

```bash
node -v
npm -v
firebase --version
```

## Project layout

Expected structure:

```text
functions/
├─ package.json
├─ tsconfig.json
├─ src/
│  ├─ index.ts
│  ├─ auth/
│  ├─ communities/
│  ├─ gameLogs/
│  ├─ odds/
│  ├─ brackets/
│  ├─ shared/
│  └─ types/
└─ test/
```

## 1) Install dependencies

From repo root:

```bash
cd functions
npm install
```

For CI parity:

```bash
npm ci
```

## 2) Firebase auth and project selection

Login:

```bash
firebase login
```

List projects:

```bash
firebase projects:list
```

Use default project (usually `dev` for local work):

```bash
firebase use <project-id>
```

## 3) Local environment configuration

Use Firebase Functions config/params for non-secret runtime values.

If using `.env` files (2nd gen functions):

- `.env` for local defaults
- `.env.dev`, `.env.prod` for environment-specific values

Never commit real secrets. Use Secret Manager for production secrets.

## 4) Run emulators locally

From repo root (recommended):

```bash
firebase emulators:start
```

Or just functions:

```bash
firebase emulators:start --only functions
```

If your functions depend on Firestore/Auth triggers, run those emulators too:

```bash
firebase emulators:start --only functions,firestore,auth,storage
```

## 5) Build, lint, test

From `functions/`:

```bash
npm run lint
npm run typecheck
npm test
npm run build
```

Recommended `package.json` scripts:

```json
{
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "lint": "eslint .",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "serve": "firebase emulators:start --only functions",
    "deploy": "firebase deploy --only functions"
  }
}
```

## 6) Deploy

Deploy to currently selected project:

```bash
firebase deploy --only functions
```

Deploy specific function only:

```bash
firebase deploy --only functions:<functionName>
```

Safer promotion flow:

1. Merge to `main`
2. Deploy to `dev` and run smoke tests
3. Deploy to `prod`

## 7) Implementation conventions

- Keep handlers thin; move domain logic into service modules.
- Validate input at function boundary.
- Return typed error responses with stable error codes.
- Keep idempotency in mind for event-driven triggers.
- For odds recalculation:
  - Trigger on `gameLog` create/update/delete
  - Recompute both `overallOdds` and `communityOdds`
- For brackets:
  - Support `COMMUNITY_ODDS`, `MANUAL`, and `RANDOM` seeding.

## 8) Testing strategy

- **Unit tests:** odds math, tie-break logic, seeding algorithms, payload validation.
- **Integration tests:** emulator tests for triggers, Firestore writes, and permission boundaries.
- **Contract tests:** verify response/error shape for callable/HTTP functions.

## 9) Observability

- Use structured logs (`logger.info/error`) with context fields (`communityId`, `gameLogId`, `profileId`).
- Track failure rates for:
  - odds recalculation
  - bracket generation
  - invite validation

## 10) Troubleshooting

### Functions emulator not starting
- Ensure Firebase CLI is updated.
- Check `firebase.json` has functions config.
- Check for port conflicts.

### TypeScript build fails
- Run `npm install` again and `npm run typecheck`.
- Verify Node version matches project requirement.

### Deploy permission denied
- Confirm correct Firebase project selected (`firebase use`).
- Confirm IAM role includes Cloud Functions deploy permissions.

### Trigger runs but data not updated
- Check emulator/prod logs for runtime errors.
- Verify collection/document paths in trigger definitions.
- Confirm security rules allow expected write path for function runtime.

## 11) Security checklist (before prod deploy)

- No secrets in code or committed env files
- Input validation on every external entry point
- Least-privilege IAM roles
- Firestore and Storage rules reviewed and emulator-tested
- Error messages do not leak internal details
