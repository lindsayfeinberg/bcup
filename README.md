# bcup

`bcup` is an iPhone app for private drinking-game communities focused on social game logging, odds tracking, and community brackets.

This README is the entry point for contributors and summarizes the project docs in `docs/`.

## Project status

- Planning/bootstrapping phase
- Core folders exist: `ios/`, `functions/`, `docs/`
- Detailed requirements and implementation tasks are documented in `docs/`

## Docs index

- Product requirements: `docs/specs.md`
- Build plan and task tracker: `docs/todo.md`
- iOS local setup: `ios/README.md`
- Cloud Functions setup: `functions/README.md`

## V1 scope (from PRD)

- Invite-only private communities
- Google sign-in plus one-time 21+ self-confirmation
- Game logging with required photo evidence
- Manual winners/losers selection for game logs
- Odds tracking:
  - `overallOdds` across all communities
  - `communityOdds` scoped to a community
- Brackets with seeding methods:
  - `COMMUNITY_ODDS`
  - `MANUAL`
  - `RANDOM`

Primary game focus for V1 is `PONG`, with basic logging support for `BEER_BALL`, `BATTLE_PONG`, and `BASEBALL`.

## Tech stack

- iOS client: Swift + SwiftUI
- Auth/Backend platform: Firebase + Google Cloud
- Database: Cloud Firestore
- Storage: Firebase Storage
- Server logic: Cloud Functions for Firebase
- Analytics/crash: Firebase Analytics + Crashlytics

## Repository structure

```text
bcup/
├─ docs/
│  ├─ specs.md
│  └─ todo.md
├─ ios/
│  └─ README.md
└─ functions/
   └─ README.md
```

## Quick start

### 1) Read project docs

1. Read `docs/specs.md` for requirements, flows, and data model.
2. Read `docs/todo.md` for dependency-ordered tasks and checkpoints.

### 2) Set up iOS environment

Follow `ios/README.md`.

At minimum:

```bash
cd ios
open bcup.xcodeproj
```

### 3) Set up Cloud Functions environment

Follow `functions/README.md`.

At minimum:

```bash
cd functions
npm install
```

## Day-to-day development commands

### iOS

Build from CLI:

```bash
cd ios
xcodebuild \
  -project bcup.xcodeproj \
  -scheme bcup \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  build
```

Test from CLI:

```bash
cd ios
xcodebuild \
  -project bcup.xcodeproj \
  -scheme bcup \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  test
```

### Cloud Functions

```bash
cd functions
npm ci
npm run lint
npm run typecheck
npm test
npm run build
```

## Team workflow

- Work from tasks in `docs/todo.md` (for example: `T01.3`).
- Keep PRs scoped to one task/subtask whenever possible.
- Use shared checkpoints from the task plan:
  - `C01` after contracts/data model lock
  - `C02` mid game-log implementation parity check
  - `C03` bracket UX/backend alignment
  - `C04` release readiness signoff

## Environment model

Use separate Firebase projects:

- `dev` for local development
- `staging` for QA
- `prod` for release

Keep secrets out of source control. Use environment-specific config and Secret Manager for production secrets.
