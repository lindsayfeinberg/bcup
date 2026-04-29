import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  assertPlatformAdmin,
  isPlatformAdminToken,
  newEnvelope,
} from "./adminAuth.js";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const region = "us-central1";

export {isPlatformAdminToken};

/**
 * @param {unknown} v Callable payload field.
 * @return {string[]} Trimmed non-empty strings.
 */
function trimStringArray(v: unknown): string[] {
  if (!Array.isArray(v)) {
    return [];
  }
  const out: string[] = [];
  for (const x of v) {
    if (typeof x === "string" && x.trim()) {
      out.push(x.trim());
    }
  }
  return out;
}

/**
 * @param {unknown} v Callable payload field.
 * @return {string | null} Trimmed string or null.
 */
function optionalTrimmedString(v: unknown): string | null {
  if (v === null || v === undefined) {
    return null;
  }
  if (typeof v !== "string") {
    return null;
  }
  const t = v.trim();
  return t.length ? t : null;
}

/**
 * @param {unknown} v Notes field.
 * @return {string | null}
 */
function optionalNotes(v: unknown): string | null {
  if (v === null || v === undefined) {
    return null;
  }
  if (typeof v !== "string") {
    return null;
  }
  const t = v.trim();
  return t.length ? t : null;
}

/**
 * Stats maps from clients (Firestore-compatible plain objects).
 * @param {unknown} v Payload field (null clears the map on the log).
 * @return {Record<string, unknown> | null}
 */
function statsMapOrNull(v: unknown): Record<string, unknown> | null {
  if (v === null) {
    return null;
  }
  if (typeof v !== "object" || Array.isArray(v)) {
    throw new HttpsError("invalid-argument", "Invalid stats map");
  }
  return v as Record<string, unknown>;
}

/**
 * @param {Record<string, unknown>} data Callable payload.
 * @param {string} key Stats field name.
 * @return {Record<string, unknown> | null}
 */
function requireStatsKey(
  data: Record<string, unknown>,
  key: string
): Record<string, unknown> | null {
  if (!Object.prototype.hasOwnProperty.call(data, key)) {
    throw new HttpsError("invalid-argument", `Missing ${key}`);
  }
  return statsMapOrNull(data[key]);
}

/**
 * Deletes a `gameLogs/{gameLogId}` document using the Admin SDK so
 * `onGameLogDeleted` runs (odds recompute + bracket undo when linked).
 *
 * Auth: Firebase Auth custom claim `platformAdmin: true` on the caller.
 */
export const adminDeleteGameLog = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const gameLogId =
    typeof request.data?.gameLogId === "string" ?
      request.data.gameLogId.trim() :
      "";
  if (!gameLogId) {
    throw new HttpsError("invalid-argument", "gameLogId is required");
  }

  const ref = db.collection("gameLogs").doc(gameLogId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Game log not found");
  }

  const data = snap.data() ?? {};
  const communityId =
    typeof data.communityId === "string" ? data.communityId : "";

  const batch = db.batch();
  batch.delete(ref);

  const auditRef = db.collection("adminActions").doc();
  batch.set(auditRef, {
    actorUid: request.auth!.uid,
    action: "deleteGameLog",
    targetGameLogId: gameLogId,
    communityId: communityId || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();

  logger.info("adminDeleteGameLog", {
    gameLogId,
    communityId,
    actorUid: request.auth!.uid,
    auditId: auditRef.id,
  });

  return newEnvelope({
    deletedGameLogId: gameLogId,
    auditActionId: auditRef.id,
  });
});

/**
 * Updates outcome-related fields on `gameLogs/{gameLogId}` using the Admin SDK
 * so operators can correct winners/losers without being the log creator.
 *
 * Auth: Firebase Auth custom claim `platformAdmin: true` on the caller.
 */
export const adminUpdateGameLog = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const gameLogId =
    typeof request.data?.gameLogId === "string" ?
      request.data.gameLogId.trim() :
      "";
  if (!gameLogId) {
    throw new HttpsError("invalid-argument", "gameLogId is required");
  }

  const data = request.data as Record<string, unknown>;
  const participantProfileIds = trimStringArray(data.participantProfileIds);
  const winnerProfileIds = trimStringArray(data.winnerProfileIds);
  const loserProfileIds = trimStringArray(data.loserProfileIds);
  const photoUrls = trimStringArray(data.photoUrls);

  if (!participantProfileIds.length) {
    throw new HttpsError(
      "invalid-argument",
      "participantProfileIds must be a non-empty array of strings"
    );
  }
  if (!winnerProfileIds.length || !loserProfileIds.length) {
    throw new HttpsError(
      "invalid-argument",
      "winnerProfileIds and loserProfileIds must each be non-empty"
    );
  }
  if (photoUrls.length !== 1) {
    throw new HttpsError(
      "invalid-argument",
      "photoUrls must contain exactly one combined image URL"
    );
  }

  const winnerSet = new Set(winnerProfileIds);
  const loserSet = new Set(loserProfileIds);
  for (const w of winnerSet) {
    if (loserSet.has(w)) {
      throw new HttpsError(
        "invalid-argument",
        "winnerProfileIds and loserProfileIds must not overlap"
      );
    }
  }
  const participantSet = new Set(participantProfileIds);
  for (const id of [...winnerSet, ...loserSet]) {
    if (!participantSet.has(id)) {
      throw new HttpsError(
        "invalid-argument",
        "All winner and loser profile ids must appear in participantProfileIds"
      );
    }
  }

  const ref = db.collection("gameLogs").doc(gameLogId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Game log not found");
  }

  const existing = snap.data() ?? {};
  const communityId =
    typeof existing.communityId === "string" ? existing.communityId : "";

  const mvpProfileId = optionalTrimmedString(data.mvpProfileId);
  const lvpProfileId = optionalTrimmedString(data.lvpProfileId);
  const notes = optionalNotes(data.notes);

  const pongStats = requireStatsKey(data, "pongStats");
  const beerBallStats = requireStatsKey(data, "beerBallStats");
  const battlePongStats = requireStatsKey(data, "battlePongStats");
  const baseballStats = requireStatsKey(data, "baseballStats");
  const crossfireStats = requireStatsKey(data, "crossfireStats");

  const updatePayload: Record<string, unknown> = {
    participantProfileIds,
    winnerProfileIds,
    loserProfileIds,
    mvpProfileId: mvpProfileId ?? null,
    lvpProfileId: lvpProfileId ?? null,
    photoUrls,
    notes: notes ?? null,
    pongStats,
    beerBallStats,
    battlePongStats,
    baseballStats,
    crossfireStats,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  const auditRef = db.collection("adminActions").doc();
  const batch = db.batch();
  // Firestore Admin typings are stricter than our validated plain-object patch.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  batch.update(ref, updatePayload as any);
  batch.set(auditRef, {
    actorUid: request.auth!.uid,
    action: "updateGameLog",
    targetGameLogId: gameLogId,
    communityId: communityId || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  logger.info("adminUpdateGameLog", {
    gameLogId,
    communityId,
    actorUid: request.auth!.uid,
    auditId: auditRef.id,
  });

  return newEnvelope({
    updatedGameLogId: gameLogId,
    auditActionId: auditRef.id,
  });
});
