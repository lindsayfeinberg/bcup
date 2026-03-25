# T12.1 Dev UAT Execution Record

Status: In Progress (handoff-ready)  
Owner: Maya + partner  
Environment: `dev` Firebase backend, iOS only

## 1) Session metadata

- Date/time started: `2026-03-25 15:31:48 EDT`
- Git branch: `maya`
- Git commit: `5899fbc42649f47bef7dc878518d0344133ecba2`
- Project/scheme check: `xcodebuild -list -project ios/bitchcup/bitchcup.xcodeproj` (scheme `bitchcup` found)
- Simulator inventory checked via `xcrun simctl list devices available`

## 2) What was completed before handoff

- Created UAT folder: `docs/uat/`
- Confirmed acceptance criteria source: `docs/acceptance-criteria.md`
- Confirmed plan scope: full checklist (feature sections 1-7 and testing checklist A-F)
- Began automated evidence run using UI tests:
  - Attempt 1 command:
    - `xcodebuild test -project ios/bitchcup/bitchcup.xcodeproj -scheme bitchcup -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:bitchcupUITests`
  - Result:
    - Failed destination resolution (`Unable to find a device matching ... OS:latest`)
  - Attempt 2 command:
    - `xcodebuild test -project ios/bitchcup/bitchcup.xcodeproj -scheme bitchcup -destination "platform=iOS Simulator,name=iPhone 16,OS=18.6" -only-testing:bitchcupUITests`
  - Result:
    - Spawn aborted in Cursor terminal host (`Command failed to spawn: Aborted`)

## 3) Current blocker

Primary blocker for UAT evidence collection in this session:

- Embedded terminal instability for long simulator test process.
- Recommendation: continue from macOS Terminal app or Xcode Test runner (not embedded terminal).

## 4) Partner pickup steps (clean slate)

From repo root (`/Users/mayamarkus-malone/Documents/Personal_CS/bcup`):

1. Confirm simulator destination:
   - `xcrun simctl list devices available`
2. Run UI tests from macOS Terminal:
   - `xcodebuild test -project ios/bitchcup/bitchcup.xcodeproj -scheme bitchcup -destination "platform=iOS Simulator,id=99FC3826-FEA5-4BAB-B272-AAA8AC29E6D2" -only-testing:bitchcupUITests`
3. If UI tests pass, proceed with manual/functional checklist validation in `dev` for remaining acceptance bullets.
4. Record every criterion result in Section 6 matrix below (`Pass` / `Fail` / `Blocked`).
5. Log each fail/blocked item in Section 7 defects table.
6. After fixes, execute rerun subset in Section 8 and update final status.

Notes:
- Using simulator **ID** avoids destination-name ambiguity.
- If this still fails in terminal, run directly in Xcode (`Product > Test`) with `bitchcupUITests`.

## 5) Acceptance criteria source map

Source of truth: `docs/acceptance-criteria.md`

- Feature criteria:
  - `AC-1.x` Authentication and onboarding
  - `AC-2.x` Communities
  - `AC-3.x` Game logging
  - `AC-4.x` Feed and profile stats surfaces
  - `AC-5.x` Odds engine
  - `AC-6.x` Brackets
  - `AC-7.x` Security and privacy
- Testing checklist:
  - `CHK-A.x` Data/API contracts
  - `CHK-B.x` Firestore rules
  - `CHK-C.x` End-to-end
  - `CHK-D.x` Odds correctness
  - `CHK-E.x` Reliability/UX
  - `CHK-F.x` Release readiness

## 6) Traceability matrix (fill during execution)

Use this table to map each acceptance item to evidence.

| ID | Source bullet (short) | Test steps/evidence target | Result | Evidence | Defect |
|---|---|---|---|---|---|
| AC-1.1 | Google sign-in works | Complete sign-in flow | Not Run |  |  |
| AC-1.2 | First login requires 21+ | New user flow -> age gate | Not Run |  |  |
| AC-1.3 | Set displayName | Onboarding profile setup | Not Run |  |  |
| AC-1.4 | Set profile photo (if required) | Onboarding photo path | Not Run |  |  |
| AC-1.5 | ageConfirmed21PlusAt + onboardingCompleteAt persist | Verify profile document fields | Not Run |  |  |
| AC-1.6 | Returning user bypasses onboarding | Relaunch signed-in complete user | Not Run |  |  |
| AC-2.1 | Create private community | Create flow success | Not Run |  |  |
| AC-2.2 | inviteCode + inviteLink valid | Verify generated values usable | Not Run |  |  |
| AC-2.3 | Join by valid invite | Join flow success | Not Run |  |  |
| AC-2.4 | Duplicate membership blocked | Attempt re-join same user | Not Run |  |  |
| AC-2.5 | Invalid/expired invite shows retryable error | Invalid code path | Not Run |  |  |
| AC-2.6 | Member roster accurate | Compare expected members | Not Run |  |  |
| AC-3.1 | Create game log with required fields | Submit valid log | Not Run |  |  |
| AC-3.2 | Block submit without photo | Try submit with no photo | Not Run |  |  |
| AC-3.3 | Winners/losers from participants | Attempt invalid participant refs | Not Run |  |  |
| AC-3.4 | Same profile not in both winner/loser | Attempt overlap | Not Run |  |  |
| AC-3.5 | Creator-only edit | Non-creator edit attempt | Not Run |  |  |
| AC-3.6 | Creator-only delete | Non-creator delete attempt | Not Run |  |  |
| AC-3.7 | Failed submit preserves state + retry | Force failure then retry | Not Run |  |  |
| AC-4.1 | Home feed scoped to memberships | Cross-community visibility check | Not Run |  |  |
| AC-4.2 | Feed cards render required data | Validate card fields | Not Run |  |  |
| AC-4.3 | Community filter updates results | Toggle filter states | Not Run |  |  |
| AC-4.4 | Profile private view stats/history | Validate profile view | Not Run |  |  |
| AC-4.5 | Empty states for no communities/logs | Trigger empty cases | Not Run |  |  |
| AC-5.1 | Log create/update/delete triggers odds recompute | Observe before/after odds | Not Run |  |  |
| AC-5.2 | profiles.overallOdds contract | Validate computed value | Not Run |  |  |
| AC-5.3 | memberships.communityOdds contract | Validate computed value | Not Run |  |  |
| AC-5.4 | Zero-game fallback contract | Verify fallback behavior | Not Run |  |  |
| AC-5.5 | Deterministic tie-break stable | Re-run tie scenario | Not Run |  |  |
| AC-6.1 | Bracket participants auto-populated | Create bracket and inspect participants | Not Run |  |  |
| AC-6.2 | Seeding method supports all 3 | COMMUNITY_ODDS/MANUAL/RANDOM | Not Run |  |  |
| AC-6.3 | Odds seeding fallback + tie-break | Validate seeded order | Not Run |  |  |
| AC-6.4 | Match updates advance bracket | Log result and inspect next round | Not Run |  |  |
| AC-6.5 | Completed bracket persists | Return and view completed bracket | Not Run |  |  |
| AC-7.1 | Non-members cannot read community-scoped data | Attempt unauthorized access | Not Run |  |  |
| AC-7.2 | Members only access own communities | Cross-community check | Not Run |  |  |
| AC-7.3 | Creator-only log edit/delete enforced | Security validation | Not Run |  |  |
| AC-7.4 | Server-owned derived fields not client-writable | Attempt direct write | Not Run |  |  |
| CHK-A.1 | Data contracts conformance | Field/type/default verification | Not Run |  |  |
| CHK-A.2 | API shapes conform | Request/response/error verification | Not Run |  |  |
| CHK-A.3 | Invalid enums rejected | Submit invalid enum values | Not Run |  |  |
| CHK-B.1 | Own profile read/write only | Rules validation | Not Run |  |  |
| CHK-B.2 | Non-member blocked for community data | Rules validation | Not Run |  |  |
| CHK-B.3 | Member limited to own communities | Rules validation | Not Run |  |  |
| CHK-B.4 | Non-creator blocked for log update/delete | Rules validation | Not Run |  |  |
| CHK-B.5 | Membership ownership constraints enforced | Rules validation | Not Run |  |  |
| CHK-C.1 | New user onboarding e2e | Sign-in -> 21+ -> profile -> feed | Not Run |  |  |
| CHK-C.2 | Returning user bypasses onboarding | Relaunch with complete profile | Not Run |  |  |
| CHK-C.3 | Create/join community e2e | End-to-end flow | Not Run |  |  |
| CHK-C.4 | Create/update/delete log e2e | End-to-end flow | Not Run |  |  |
| CHK-C.5 | Bracket create/match update e2e | End-to-end flow | Not Run |  |  |
| CHK-D.1 | Win-rate calculations correct | Scenario verification | Not Run |  |  |
| CHK-D.2 | Zero denominator fallback | Scenario verification | Not Run |  |  |
| CHK-D.3 | Update/delete recalc correctness | Scenario verification | Not Run |  |  |
| CHK-D.4 | Tie-case stable ordering | Re-run tie scenario | Not Run |  |  |
| CHK-E.1 | Upload failure clear retry | Failure UX validation | Not Run |  |  |
| CHK-E.2 | Network/API errors user-safe | Error UX validation | Not Run |  |  |
| CHK-E.3 | No missing index errors | Monitor logs/console | Not Run |  |  |
| CHK-E.4 | Happy paths crash-free on simulator | Run critical flows | In Progress | UI test run attempted; destination/spawn blocked | DEF-001 |
| CHK-F.1 | CI passes | Verify latest CI status | Not Run |  |  |
| CHK-F.2 | Dev smoke tests pass | Run smoke suite | Not Run |  |  |
| CHK-F.3 | Prod deploy success | Out of scope for iOS-only dev UAT execution session | Blocked | Requires release stage owner | DEF-002 |
| CHK-F.4 | Post-deploy smoke checks | Out of scope for iOS-only dev UAT execution session | Blocked | Requires prod deploy | DEF-002 |

## 7) Defects / blockers log

| Defect ID | Severity | Area | Summary | Repro | Expected | Actual | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| DEF-001 | Medium | UAT infrastructure | UI test command unstable in embedded terminal | Run `xcodebuild test ...` in Cursor terminal | UI tests launch on simulator | Destination ambiguity on first run; spawn abort on second run | QA/UAT runner | Open |
| DEF-002 | Low | Scope/sequence | CHK-F.3/F.4 require production deploy stage | Execute full acceptance checklist in dev-only session | Dev UAT should cover releasable subset | Prod-specific checks cannot be executed before release stage | Release owner | Open |

## 8) Rerun subset after fixes

Rerun these in order after resolving DEF-001:

1. `bitchcupUITests` run on fixed simulator destination (by ID)
2. `CHK-E.4` crash-free happy path verification
3. All critical e2e rows: `CHK-C.1` to `CHK-C.5`
4. Any rows marked `Fail` or `Blocked` in Section 6

## 9) Completion criteria for T12.1

Mark `T12.1` complete only when:

- All rows in Section 6 are set to `Pass`, `Fail`, or `Blocked` with evidence links.
- Every `Fail`/`Blocked` row has a defect reference in Section 7.
- Rerun outcomes are captured in Section 8.

---

Handoff note: this file is prepared so a partner can continue from a clean slate without re-discovery. Continue by executing pickup steps in Section 4 and filling Section 6 progressively.

