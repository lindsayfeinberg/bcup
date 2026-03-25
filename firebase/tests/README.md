# Security rules integration tests

Runs [Firestore](https://firebase.google.com/docs/firestore/security/get-started) and [Storage](https://firebase.google.com/docs/storage/security) rules against the local emulators via [`@firebase/rules-unit-testing`](https://firebase.google.com/docs/rules/unit-tests).

## Requirements

- Node 20+
- Java 17+ (for the Firestore emulator; CI uses Temurin 17)

## Commands

From this directory:

```bash
npm ci
npm test
```

`npm test` starts Firestore + Storage emulators (using the repo root `firebase.json`), then runs Jest with `jest.config.cjs`.

## Pin note

This package pins `firebase-tools@12.9.1` and invokes the **local** `firebase` binary so `npx firebase` does not pick up a globally installed CLI that may require Java 21+.
