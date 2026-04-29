import * as admin from "firebase-admin";
import type {Query} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {assertPlatformAdmin, newEnvelope} from "./adminAuth.js";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const region = "us-central1";

const MAX_PAGE = 100;
const DEFAULT_PAGE = 25;

/**
 * @param {unknown} n Requested page size.
 * @return {number} Clamped page size.
 */
function clampPageSize(n: unknown): number {
  const x = typeof n === "number" && !Number.isNaN(n) ? Math.floor(n) : DEFAULT_PAGE;
  return Math.min(MAX_PAGE, Math.max(1, x));
}

const COMMUNITY_NAME_BATCH = 10;
const PROFILE_NAME_BATCH = 10;

/**
 * Loads `communities/{id}.name` for a set of ids (batched `getAll`).
 * @param {string[]} communityIds Community document ids referenced by logs.
 * @return {Promise<Map<string, string>>} Map id → display name (may be empty).
 */
async function communityNamesForIds(
  communityIds: string[]
): Promise<Map<string, string>> {
  const unique = [...new Set(communityIds.map((x) => x.trim()).filter(Boolean))];
  const map = new Map<string, string>();
  for (let i = 0; i < unique.length; i += COMMUNITY_NAME_BATCH) {
    const slice = unique.slice(i, i + COMMUNITY_NAME_BATCH);
    const refs = slice.map((id) => db.collection("communities").doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (!s.exists) {
        continue;
      }
      const n = s.data()?.name;
      map.set(s.id, typeof n === "string" ? n : "");
    }
  }
  return map;
}

/**
 * Loads `profiles/{id}.displayName` for a set of ids (batched `getAll`).
 * @param {string[]} profileIds Profile ids referenced by admin actions.
 * @return {Promise<Map<string, string>>} Map id → display name (may be empty).
 */
async function profileNamesForIds(
  profileIds: string[]
): Promise<Map<string, string>> {
  const unique = [...new Set(profileIds.map((x) => x.trim()).filter(Boolean))];
  const map = new Map<string, string>();
  for (let i = 0; i < unique.length; i += PROFILE_NAME_BATCH) {
    const slice = unique.slice(i, i + PROFILE_NAME_BATCH);
    const refs = slice.map((id) => db.collection("profiles").doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) {
      if (!s.exists) {
        continue;
      }
      const n = s.data()?.displayName;
      map.set(s.id, typeof n === "string" ? n : "");
    }
  }
  return map;
}

/**
 * Paginated `communities` list (document id order) for platform operators.
 */
export const adminListCommunities = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const pageSize = clampPageSize(request.data?.pageSize);
  const startAfterId =
    typeof request.data?.startAfterCommunityId === "string" ?
      request.data.startAfterCommunityId.trim() :
      "";

  let q = db
    .collection("communities")
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(pageSize);

  if (startAfterId) {
    q = q.startAfter(startAfterId);
  }

  const snap = await q.get();
  const items = snap.docs.map((d) => {
    const v = d.data();
    return {
      communityId: d.id,
      name: typeof v.name === "string" ? v.name : "",
      memberCount: typeof v.memberCount === "number" ? v.memberCount : 0,
      createdByProfileId:
        typeof v.createdByProfileId === "string" ? v.createdByProfileId : "",
    };
  });

  const last = snap.docs[snap.docs.length - 1];
  const nextCursor = last ? last.id : null;

  logger.info("adminListCommunities", {count: items.length, actorUid: request.auth!.uid});

  return newEnvelope({
    items,
    nextCursor,
    hasMore: snap.size === pageSize,
  });
});

/**
 * Paginated `gameLogs` list (newest first). Optional `communityId` filter.
 */
export const adminListGameLogs = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const pageSize = clampPageSize(request.data?.pageSize);
  const communityId =
    typeof request.data?.communityId === "string" ?
      request.data.communityId.trim() :
      "";
  const cur = request.data?.cursor as
    | {createdAtMillis?: unknown; documentId?: unknown}
    | undefined;
  const cursorCreatedAt =
    cur && typeof cur.createdAtMillis === "number" && !Number.isNaN(cur.createdAtMillis) ?
      cur.createdAtMillis :
      null;
  const cursorDocId =
    cur && typeof cur.documentId === "string" ? cur.documentId.trim() : "";

  let q: Query = db.collection("gameLogs");
  if (communityId) {
    q = q.where("communityId", "==", communityId);
  }
  q = q
    .orderBy("createdAt", "desc")
    .orderBy(admin.firestore.FieldPath.documentId(), "desc")
    .limit(pageSize);

  if (cursorCreatedAt != null && cursorDocId) {
    const ts = admin.firestore.Timestamp.fromMillis(cursorCreatedAt);
    q = q.startAfter(ts, cursorDocId);
  }

  const snap = await q.get();
  const rawItems = snap.docs.map((d) => {
    const v = d.data();
    const createdAt = v.createdAt as admin.firestore.Timestamp | undefined;
    return {
      gameLogId: d.id,
      communityId: typeof v.communityId === "string" ? v.communityId : "",
      gameType: typeof v.gameType === "string" ? v.gameType : "",
      createdByProfileId:
        typeof v.createdByProfileId === "string" ? v.createdByProfileId : "",
      createdAtMillis: createdAt ? createdAt.toMillis() : 0,
    };
  });

  const nameMap = await communityNamesForIds(
    rawItems.map((it) => it.communityId)
  );
  const items = rawItems.map((it) => ({
    ...it,
    communityName: nameMap.get(it.communityId) ?? "",
  }));

  const last = snap.docs[snap.docs.length - 1];
  let nextCursor: {createdAtMillis: number; documentId: string} | null = null;
  if (last) {
    const v = last.data();
    const createdAt = v.createdAt as admin.firestore.Timestamp | undefined;
    nextCursor = {
      createdAtMillis: createdAt ? createdAt.toMillis() : 0,
      documentId: last.id,
    };
  }

  logger.info("adminListGameLogs", {
    count: items.length,
    communityId: communityId || null,
    actorUid: request.auth!.uid,
  });

  return newEnvelope({
    items,
    nextCursor,
    hasMore: snap.size === pageSize,
  });
});

/**
 * Paginated `adminActions` audit feed (newest first).
 * Optional filters: `action`, `targetCommunityId`.
 */
export const adminListActions = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const pageSize = clampPageSize(request.data?.pageSize);
  const actionFilter =
    typeof request.data?.action === "string" ?
      request.data.action.trim() :
      "";
  const targetCommunityId =
    typeof request.data?.targetCommunityId === "string" ?
      request.data.targetCommunityId.trim() :
      "";
  const cur = request.data?.cursor as
    | {createdAtMillis?: unknown; documentId?: unknown}
    | undefined;
  const cursorCreatedAt =
    cur && typeof cur.createdAtMillis === "number" && !Number.isNaN(cur.createdAtMillis) ?
      cur.createdAtMillis :
      null;
  const cursorDocId =
    cur && typeof cur.documentId === "string" ? cur.documentId.trim() : "";

  let q: Query = db.collection("adminActions");
  if (actionFilter) {
    q = q.where("action", "==", actionFilter);
  }
  if (targetCommunityId) {
    q = q.where("targetCommunityId", "==", targetCommunityId);
  }
  q = q
    .orderBy("createdAt", "desc")
    .orderBy(admin.firestore.FieldPath.documentId(), "desc")
    .limit(pageSize);

  if (cursorCreatedAt != null && cursorDocId) {
    const ts = admin.firestore.Timestamp.fromMillis(cursorCreatedAt);
    q = q.startAfter(ts, cursorDocId);
  }

  const snap = await q.get();
  const rawItems = snap.docs.map((d) => {
    const v = d.data();
    const createdAt = v.createdAt as admin.firestore.Timestamp | undefined;
    return {
      adminActionId: d.id,
      actorUid: typeof v.actorUid === "string" ? v.actorUid : "",
      action: typeof v.action === "string" ? v.action : "",
      targetCommunityId:
        typeof v.targetCommunityId === "string" ? v.targetCommunityId : "",
      targetProfileId:
        typeof v.targetProfileId === "string" ? v.targetProfileId : "",
      targetGameLogId:
        typeof v.targetGameLogId === "string" ? v.targetGameLogId : "",
      targetMessageId:
        typeof v.targetMessageId === "string" ? v.targetMessageId : "",
      createdAtMillis: createdAt ? createdAt.toMillis() : 0,
    };
  });
  const actorNameMap = await profileNamesForIds(
    rawItems.map((it) => it.actorUid)
  );
  const items = rawItems.map((it) => ({
    ...it,
    actorDisplayName: actorNameMap.get(it.actorUid) ?? "",
  }));

  const last = snap.docs[snap.docs.length - 1];
  let nextCursor: {createdAtMillis: number; documentId: string} | null = null;
  if (last) {
    const v = last.data();
    const createdAt = v.createdAt as admin.firestore.Timestamp | undefined;
    nextCursor = {
      createdAtMillis: createdAt ? createdAt.toMillis() : 0,
      documentId: last.id,
    };
  }

  logger.info("adminListActions", {
    count: items.length,
    action: actionFilter || null,
    targetCommunityId: targetCommunityId || null,
    actorUid: request.auth!.uid,
  });

  return newEnvelope({
    items,
    nextCursor,
    hasMore: snap.size === pageSize,
  });
});

/**
 * Removes a league membership and decrements `communities.memberCount`.
 */
export const adminKickMember = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const communityId =
    typeof request.data?.communityId === "string" ?
      request.data.communityId.trim() :
      "";
  const profileId =
    typeof request.data?.profileId === "string" ?
      request.data.profileId.trim() :
      "";
  if (!communityId || !profileId) {
    throw new HttpsError(
      "invalid-argument",
      "communityId and profileId are required"
    );
  }

  const membershipId = `${communityId}_${profileId}`;
  const membershipRef = db.collection("memberships").doc(membershipId);
  const communityRef = db.collection("communities").doc(communityId);
  const auditRef = db.collection("adminActions").doc();

  await db.runTransaction(async (t) => {
    const [ms, cs] = await Promise.all([t.get(membershipRef), t.get(communityRef)]);
    if (!ms.exists) {
      throw new HttpsError("not-found", "Membership not found");
    }
    if (!cs.exists) {
      throw new HttpsError("not-found", "Community not found");
    }
    const count =
      typeof cs.data()?.memberCount === "number" ? cs.data()!.memberCount : 0;
    t.delete(membershipRef);
    t.update(communityRef, {
      memberCount: Math.max(0, count - 1),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    t.set(auditRef, {
      actorUid: request.auth!.uid,
      action: "kickMember",
      targetCommunityId: communityId,
      targetProfileId: profileId,
      membershipId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  logger.info("adminKickMember", {
    communityId,
    profileId,
    actorUid: request.auth!.uid,
    auditId: auditRef.id,
  });

  return newEnvelope({
    membershipId,
    auditActionId: auditRef.id,
  });
});

/**
 * Hard-deletes a league board message (Admin SDK; clients cannot delete per rules).
 */
export const adminDeleteLeagueMessage = onCall({region}, async (request) => {
  assertPlatformAdmin(request.auth);

  const communityId =
    typeof request.data?.communityId === "string" ?
      request.data.communityId.trim() :
      "";
  const messageId =
    typeof request.data?.messageId === "string" ?
      request.data.messageId.trim() :
      "";
  if (!communityId || !messageId) {
    throw new HttpsError(
      "invalid-argument",
      "communityId and messageId are required"
    );
  }

  const ref = db
    .collection("communities")
    .doc(communityId)
    .collection("messages")
    .doc(messageId);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError("not-found", "Message not found");
  }

  const batch = db.batch();
  batch.delete(ref);
  const auditRef = db.collection("adminActions").doc();
  batch.set(auditRef, {
    actorUid: request.auth!.uid,
    action: "deleteLeagueMessage",
    targetCommunityId: communityId,
    targetMessageId: messageId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await batch.commit();

  logger.info("adminDeleteLeagueMessage", {
    communityId,
    messageId,
    actorUid: request.auth!.uid,
    auditId: auditRef.id,
  });

  return newEnvelope({
    deletedMessageId: messageId,
    auditActionId: auditRef.id,
  });
});
