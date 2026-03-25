# T12.4 Incident Response Runbook (App + Firebase)

## Purpose
Provide a repeatable process to:
- Detect production incidents quickly
- Classify likely root cause (iOS build vs Firebase Rules/Functions vs data integrity)
- Mitigate immediately
- Execute the correct rollback using `rollback-runbook.md`
- Preserve evidence for follow-up

## Scope
Applies to V1 production for `bcup`:
- iOS client (Firebase Auth + Firestore + Storage + Analytics/Crashlytics)
- Firebase Firestore/Storage security rules
- Cloud Functions (game log triggers and bracket helper callables)

## Roles
- Incident Commander (IC): declares severity, assigns next steps, drives comms
- Technical Lead (TL): triage + mitigation/rollback execution (backend + iOS)
- Release Manager (RM): App Store / TestFlight actions and release gating
- Scribe: evidence capture + timeline updates

## Severity levels (use to drive urgency)
- SEV-1 (critical): app is unusable for many users OR widespread crashes OR rules block all core actions (e.g., sign-in -> feed unreachable)
- SEV-2 (major): significant functionality impacted (some crashes, major feature broken, high error rate)
- SEV-3 (minor): isolated reports, low crash rate, degraded non-core experience
- SEV-4 (monitoring): anomaly without confirmed user impact

## Detection signals (what to look at)
Check these within the first 5-15 minutes of alert:
- Crashlytics
  - Crash-free sessions drop
  - Spikes in a single top crash event
  - New stack traces correlated with the newest iOS version
- Firebase Analytics
  - Login/onboarding funnel drop (especially post-age-gate)
  - Feed load failure events (if tracked) / login success vs fail changes
- Firestore / Functions logs
  - Firestore security rule denials (common for SEV-1/2)
  - Cloud Functions errors (exceptions in `gameLogTriggers` or bracket callables)
- User-visible errors
  - “permission_denied” / “client is offline” patterns
  - Feed cards failing to render or missing expected content

## Triage timeline (first 30 minutes)
1. Confirm incident start time + affected surface
   - When did it begin? (approx)
   - Who is affected? (all users vs subset; by version)
   - What is broken? (onboarding, feed read, log create, brackets updates)
2. Identify the latest production changes
   - New iOS build release? (TestFlight/App Store version)
   - New backend release? (functions/rules/indexes deploy)
   - Any configuration change? (Firebase project, env, plist differences)
3. Classify likely root cause using symptoms
   - If crashes: iOS build issue -> proceed with iOS rollback steps
   - If rule denials: rules/rules indexes -> proceed with backend rollback
   - If odds/brackets wrong but no crashes: likely Cloud Functions logic -> proceed with functions rollback + optional backfill
4. Decide severity
   - SEV-1/2 requires rollback execution plan immediately

## Mitigation actions (do the minimum to reduce user impact)
Choose the earliest mitigation that matches the root cause:
- iOS crashes:
  - Stop distributing the bad build (TestFlight: pause/discontinue; Production: remove from sale if already live)
  - Prepare a rollback build (upload LKG build to App Store/TestFlight)
- Firestore/Storage rules denials:
  - Redeploy last-known-good Firestore rules + storage rules (and indexes if required)
  - Avoid further schema/model changes during the incident window
- Cloud Functions errors affecting derived fields / bracket progression:
  - Redeploy last-known-good Cloud Functions
  - If the bug corrupts derived fields, rollback fixes future events; plan optional backfill if user impact persists

## Evidence capture checklist (Scribe)
Collect before/while mitigating:
- Timeline: detection time, actions taken, results
- Production version info
  - iOS version(s) affected
  - Backend deploy timestamps
  - Git tag/commit hashes for “bad” release (what changed)
- Logs and screenshots
  - Crashlytics: top crash event name + stack trace ID
  - Firestore rules: rule denial messages / query path patterns
  - Functions logs: error stack traces and request IDs
- User impact metrics
  - crash-free sessions trend
  - onboarding success rate trend
  - percentage of failed requests (if available)

## Rollback decision gate
At minute ~15-25, TL and IC should answer:
- Is the incident likely caused by iOS vs backend?
- What exact component(s) changed in the “bad” release set?
- Do we rollback now, or after gathering one more log sample?

## Communication plan (minimal but consistent)
- IC posts a short status update at:
  - SEV declaration
  - rollback start
  - rollback completion + early validation result
  - incident closure
- Include: severity, what’s broken, ETA, current mitigation, next step.

## Post-incident requirements
Within 1-2 days:
- Run a short root-cause analysis:
  - What changed?
  - Why did tests/monitoring miss it?
  - What can be prevented next release?
- Update runbooks if the rollback path needed interpretation.

## Primary runbook link
Use `rollback-runbook.md` for exact rollback steps and deploy commands.

