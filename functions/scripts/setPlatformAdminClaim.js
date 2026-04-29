#!/usr/bin/env node
/**
 * One-off: set Firebase Auth custom claim `platformAdmin: true` for a user by email.
 *
 * Credentials (pick one):
 * - **Recommended (avoids USER_PROJECT_DENIED on a laptop):** download a Firebase service
 *   account JSON (Firebase Console → Project settings → Service accounts → Generate new
 *   private key), then:
 *     export GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/key.json"
 * - **Application Default:** `gcloud auth application-default login` — your Google user must
 *   have IAM on the GCP project (e.g. Service Usage Consumer + permission to manage Auth users).
 *
 * Project: `--project=ID`, or GCLOUD_PROJECT, or repo root `.firebaserc` projects.default.
 *
 * After running, sign out/in in the app so the ID token picks up custom claims.
 */

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

function readDefaultProjectFromFirebaserc() {
  const candidate = path.join(__dirname, "..", "..", ".firebaserc");
  try {
    const raw = fs.readFileSync(candidate, "utf8");
    const json = JSON.parse(raw);
    return json?.projects?.default || null;
  } catch {
    return null;
  }
}

function parseArgs(argv) {
  const revoke = argv.includes("--revoke");
  const positional = argv.filter((a) => a !== "--revoke" && !a.startsWith("--project="));
  const projectFlag = argv.find((a) => a.startsWith("--project="));
  const fromFlag = projectFlag ? projectFlag.split("=")[1] : null;
  const projectId =
    fromFlag ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    readDefaultProjectFromFirebaserc();
  const email = positional[0];
  return {revoke, projectId, email};
}

function assertGoogleApplicationCredentialsPath() {
  const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (!p) {
    return;
  }
  if (!fs.existsSync(p)) {
    console.error(
      `GOOGLE_APPLICATION_CREDENTIALS points to a missing file:\n  ${p}\n` +
        "Unset it or fix the path."
    );
    process.exit(1);
  }
}

function buildCredential() {
  const p = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (p && fs.existsSync(p)) {
    return admin.credential.cert(JSON.parse(fs.readFileSync(p, "utf8")));
  }
  return admin.credential.applicationDefault();
}

function printUserProjectDeniedHelp(projectId) {
  const pid = projectId || "YOUR_PROJECT_ID";
  console.error(`
--- Permission denied on project (serviceusage / USER_PROJECT_DENIED) ---

Your credentials can authenticate, but this principal is not allowed to
*use* APIs billed against project ${pid} (needs serviceusage.services.use).

Fix ONE of:

  A) IAM (needs a project Owner in Google Cloud Console → IAM for project "${pid}"):
     Principal: the Google account you used for "gcloud auth application-default login"
     Role: at minimum "Service Usage Consumer" (roles/serviceusage.serviceUsageConsumer)
     Often you also need a role that can edit Firebase Auth users, e.g. "Firebase Authentication Admin"
     or broader "Editor" / "Owner" on the GCP project linked to Firebase.

  B) Service account key (recommended on a laptop; avoids personal GCP IAM):
     Firebase Console → Project "${pid}" → Project settings → Service accounts → Generate new private key
     Then:
       export GOOGLE_APPLICATION_CREDENTIALS="/full/path/to/key.json"
     Re-run this script (same --project=${pid} ...).

Propagation can take a few minutes after IAM changes.
`);
}

async function main() {
  assertGoogleApplicationCredentialsPath();

  const {revoke, projectId, email} = parseArgs(process.argv.slice(2));
  if (!email || email.startsWith("--")) {
    console.error(
      "Usage: node scripts/setPlatformAdminClaim.js [--project=YOUR_PROJECT_ID] <email>\n" +
        "       node scripts/setPlatformAdminClaim.js --revoke [--project=...] <email>"
    );
    process.exit(1);
  }

  if (!projectId) {
    console.error(
      "Missing project id. Pass --project=YOUR_ID or set GCLOUD_PROJECT,\n" +
        "or set projects.default in repo root .firebaserc."
    );
    process.exit(1);
  }

  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.warn(
      "[hint] No GOOGLE_APPLICATION_CREDENTIALS: using Application Default Credentials.\n" +
        "        If you get USER_PROJECT_DENIED, set GOOGLE_APPLICATION_CREDENTIALS to a\n" +
        "        Firebase service account JSON (Console → Project settings → Service accounts).\n"
    );
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      projectId,
      credential: buildCredential(),
    });
  }

  console.log(`Using project: ${projectId}`);

  const user = await admin.auth().getUserByEmail(email);

  if (revoke) {
    const existing = user.customClaims || {};
    const next = {...existing};
    delete next.platformAdmin;
    await admin.auth().setCustomUserClaims(user.uid, next);
    console.log(`Revoked platformAdmin for ${email} (uid=${user.uid})`);
  } else {
    await admin.auth().setCustomUserClaims(user.uid, {
      ...(user.customClaims || {}),
      platformAdmin: true,
    });
    console.log(`Set platformAdmin=true for ${email} (uid=${user.uid})`);
  }
}

main().catch((err) => {
  const msg = String(err?.message || err || "");
  const projectId =
    process.argv.find((a) => a.startsWith("--project="))?.split("=")[1] ||
    process.env.GCLOUD_PROJECT ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    readDefaultProjectFromFirebaserc();

  if (msg.includes("USER_PROJECT_DENIED") || msg.includes("serviceusage.services.use")) {
    printUserProjectDeniedHelp(projectId);
  }
  console.error(err);
  process.exit(1);
});
