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
cd ios
open bcup.xcodeproj
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
cd ios
xcodebuild -resolvePackageDependencies -project bcup.xcodeproj
```

If package resolution fails in terminal, use Xcode:
- File -> Packages -> Resolve Package Versions

## 4) Firebase configuration

This app uses Firebase Auth/Firestore/Storage/Functions.

1. Download `GoogleService-Info.plist` for the iOS app from Firebase Console.
2. Add it to the app target in Xcode (`ios/bcup/Resources/` is the recommended location).
3. Ensure the file is included in the `bcup` target's "Copy Bundle Resources".

Do not commit secrets or environment-specific credentials.

## 5) Run locally

In Xcode:

- Select scheme: `bcup`
- Select simulator: e.g. `iPhone 15`
- Press Run (`Cmd+R`)

Or via CLI:

```bash
cd ios
xcodebuild \
  -project bcup.xcodeproj \
  -scheme bcup \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -configuration Debug \
  build
```

## 6) Run tests

In Xcode:
- Product -> Test (`Cmd+U`)

Or via CLI:

```bash
cd ios
xcodebuild \
  -project bcup.xcodeproj \
  -scheme bcup \
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
- Ensure `bcup` is marked as **Shared**

### Firebase not initializing
- Confirm `GoogleService-Info.plist` exists in target resources
- Confirm app bundle ID matches Firebase iOS app registration

## 9) Code conventions (iOS)

- Use feature-first folders (`Features/Auth`, `Features/Feed`, etc.)
- Keep view models free of UIKit/SwiftUI side effects where possible
- Add unit tests for business logic and UI tests for critical user flows
- Prefer small PRs and keep each PR scoped to one task/subtask from `docs/todo.md`
