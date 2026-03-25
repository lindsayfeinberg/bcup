# iOS App Setup (`ios/`)

This guide explains how to run the `bcup` iOS app locally.

## Prerequisites

- macOS with latest stable Xcode installed
- Apple ID signed into Xcode (for simulator/device tooling)
- Homebrew (recommended for tooling installs)
- CocoaPods only if the project later adopts it (not required by default)

## 1) Open the project

From the repo root:

```bash
cd ios/bitchcup
open bitchcup.xcodeproj
```

If the app is later migrated to a workspace, open:

```bash
open bcup.xcworkspace
```

## 2) Xcode first-run checks

- Open Xcode -> Settings -> Locations
  - Ensure Command Line Tools points to your current Xcode version
- Accept Apple license if prompted:

```bash
sudo xcodebuild -license accept
```

- Verify Xcode CLI:

```bash
xcodebuild -version
```

## 3) Resolve dependencies

In project directory:

```bash
cd ios/bitchcup
xcodebuild -resolvePackageDependencies -project bitchcup.xcodeproj
```

If package resolution fails in terminal, use Xcode:
- File -> Packages -> Resolve Package Versions

## 4) Firebase configuration

This app uses Firebase Auth/Firestore/Storage/Analytics (and Cloud Functions when wired server-side). **Debug and Release builds talk to Firebase in the cloud** using `GoogleService-Info.plist` — the iOS app does **not** point Auth/Firestore/Storage at local emulators by default. To use emulators again, re-add `useEmulator` / Firestore settings in `AppDelegate` (see `bitchcupApp.swift`).

1. Download `GoogleService-Info.plist` for the iOS app from Firebase Console.
2. Add it to the app target in Xcode (`ios/bcup/Resources/` is the recommended location).
3. Ensure the file is included in the `bcup` target's "Copy Bundle Resources".

Do not commit secrets or environment-specific credentials.

If you see **permission_denied** on `profiles/{uid}` in the app, the Firestore **rules in the cloud** must match this repo. From the repo root:

```bash
firebase deploy --only firestore:rules
```

The default Firebase project for CLI is `bitchcup-dev` (`.firebaserc` at the repo root). The iOS `GoogleService-Info.plist` must be for that same project.

**Firestore database ID:** Rules and indexes deploy to the database named in `firebase.json` → `firestore.database`. The iOS app uses the same ID via `AppFirestore.databaseId` (currently **`(default)`** — the Standard database in Console, *not* a separate Enterprise database named `default`). On launch, Xcode logs a line like `Firestore fingerprint — projectID=… databaseId=(default) host=…`.

**Analytics & Crashlytics (T05.6, T11.4):** The app links **Firebase Analytics** and **Firebase Crashlytics** (SPM product on the `bitchcup` target). **Debug** builds disable Crashlytics collection in `AppDelegate` (`setCrashlyticsCollectionEnabled(false)`); **Release** enables it. The **Firebase Crashlytics** run script uploads dSYMs (input paths include the built app’s `GoogleService-Info.plist`, dSYM, and `Info.plist`).

**Events we log** (custom names use a `bcup_` prefix; no PII in parameters):

| Area | What |
|------|------|
| Onboarding | `OnboardingAnalytics`: `screen_view` with `bcup_onb_*` screen names, standard `login`, custom `bcup_onb_*` funnel events (`OnboardingAnalytics.swift`) |
| Feed | `screen_view` (`bcup_feed`), `bcup_feed_load` (outcome + optional row count / error snippet), `bcup_feed_refresh` (`bcup_source=pull`), `bcup_feed_load_more_fail` |
| Profile | `screen_view` (`bcup_profile`), `bcup_profile_load` (outcome + optional `bcup_history_count` / error), `bcup_profile_history_load_more_fail` |
| Auth | `bcup_auth_sign_out` on successful log out (`AppSessionManager`) |

Crashlytics **user id** is synced from `Auth.auth().currentUser?.uid` after session resolution and cleared on sign-out (`AppSessionManager`).

Verify Analytics in Firebase Console → Analytics → DebugView with **-FIRAnalyticsDebugEnabled** (see Firebase docs).

## 5) Run locally

In Xcode:

- Select scheme: `bitchcup`
- Select simulator: e.g. `iPhone 15`
- Press Run (`Cmd+R`)

Or via CLI:

```bash
cd ios/bitchcup
xcodebuild \
  -project bitchcup.xcodeproj \
  -scheme bitchcup \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  build
```

## 6) Run tests

In Xcode:
- Product -> Test (`Cmd+U`)

Or via CLI:

```bash
cd ios/bitchcup
xcodebuild \
  -project bitchcup.xcodeproj \
  -scheme bitchcup \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  test
```

## 7) Suggested local environment strategy

Use separate Firebase projects by environment:

- `bcup-dev` for local development
- `bcup-prod` for release

Keep environment-specific config isolated (plist, bundle IDs, and any API host overrides).

## 8) Troubleshooting

### Build fails after Xcode update
- Clean build folder in Xcode (`Shift+Cmd+K`)
- Delete Derived Data:

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData
```

### "No such module" package errors
- Re-resolve package dependencies
- Restart Xcode

### Scheme not found in CI
- Xcode -> Product -> Scheme -> Manage Schemes
- Ensure `bitchcup` is marked as **Shared**

### Firebase not initializing
- Confirm `GoogleService-Info.plist` exists in target resources
- Confirm app bundle ID matches Firebase iOS app registration

## 9) Code conventions (iOS)

- Use feature-first folders (`Features/Auth`, `Features/Feed`, etc.)
- Keep view models free of UIKit/SwiftUI side effects where possible
- Add unit tests for business logic and UI tests for critical user flows
- Prefer small PRs and keep each PR scoped to one task/subtask from `docs/todo.md`
