import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

/** Hard cap on community size (joins + creator). */
export const MAX_COMMUNITY_MEMBERS = 350;

const INVITE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

/**
 * Builds an 8-character invite code.
 * @return {string} Code using an unambiguous alphabet (no I, O, 0, 1).
 */
function randomInviteCode(): string {
  let out = "";
  for (let i = 0; i < 8; i++) {
    out += INVITE_CHARS[Math.floor(Math.random() * INVITE_CHARS.length)];
  }
  return out;
}

/**
 * Resolves a code not already used by any `communities` document.
 * @return {Promise<string>} A unique invite code.
 */
async function generateUniqueInviteCode(): Promise<string> {
  for (let attempt = 0; attempt < 20; attempt++) {
    const code = randomInviteCode();
    const snap = await db.collection("communities")
      .where("inviteCode", "==", code)
      .limit(1)
      .get();
    if (snap.empty) {
      return code;
    }
  }
  throw new HttpsError("internal", "Could not allocate invite code");
}

/**
 * Callable API envelope per api-contracts.
 * @param {T} data Payload for the client.
 * @return {object} Wrapped response with meta.requestId.
 * @template T
 */
function newEnvelope<T extends Record<string, unknown>>(data: T) {
  const suffix = Math.random().toString(36).slice(2, 9);
  return {
    ok: true,
    apiVersion: "v1",
    data,
    meta: {requestId: `req_${Date.now()}_${suffix}`},
  };
}

const region = "us-central1";

export const createCommunity = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const name = typeof request.data?.name === "string" ?
    request.data.name.trim() :
    "";
  if (!name) {
    throw new HttpsError("invalid-argument", "name is required");
  }

  const uid = request.auth.uid;
  // Denormalize roster display fields onto the membership doc so the client
  // doesn't need to read other users' `profiles/*` (which is intentionally locked down by rules).
  const profileSnap = await db.collection("profiles").doc(uid).get();
  const displayName = (profileSnap.data()?.displayName as string | undefined) ?? "";
  const profilePhotoUrl = (profileSnap.data()?.profilePhotoUrl as string | undefined) ?? null;

  const communityRef = db.collection("communities").doc();
  const communityId = communityRef.id;
  const inviteCode = await generateUniqueInviteCode();
  const inviteLink = `https://bcup.app/join/${inviteCode}`;
  const membershipId = `${communityId}_${uid}`;
  const membershipRef = db.collection("memberships").doc(membershipId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  try {
    await db.runTransaction(async (t) => {
      t.set(communityRef, {
        id: communityId,
        name,
        createdByProfileId: uid,
        inviteCode,
        inviteLink,
        memberCount: 1,
        createdAt: now,
        updatedAt: now,
      });
      t.set(membershipRef, {
        id: membershipId,
        communityId,
        profileId: uid,
        displayName,
        profilePhotoUrl,
        joinedAt: now,
        communityOdds: 0,
        communityGamesPlayed: 0,
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (e) {
    logger.error("createCommunity transaction failed", e);
    throw new HttpsError("internal", "Could not create community");
  }

  return newEnvelope({communityId, inviteCode, inviteLink});
});

export const joinCommunity = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const raw = request.data?.inviteCode;
  const inviteCode = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!inviteCode) {
    throw new HttpsError("invalid-argument", "inviteCode is required");
  }

  const uid = request.auth.uid;
  // Denormalize roster display fields onto the membership doc so the client
  // doesn't need to read other users' `profiles/*` (which is intentionally locked down by rules).
  const profileSnap = await db.collection("profiles").doc(uid).get();
  const displayName = (profileSnap.data()?.displayName as string | undefined) ?? "";
  const profilePhotoUrl = (profileSnap.data()?.profilePhotoUrl as string | undefined) ?? null;

  const communities = await db.collection("communities")
    .where("inviteCode", "==", inviteCode)
    .limit(1)
    .get();

  if (communities.empty) {
    throw new HttpsError("not-found", "Invalid invite code");
  }

  const communityRef = communities.docs[0].ref;
  const communityId = communityRef.id;
  const membershipId = `${communityId}_${uid}`;
  const membershipRef = db.collection("memberships").doc(membershipId);

  try {
    await db.runTransaction(async (t) => {
      const snap = await t.get(communityRef);
      const data = snap.data();
      if (!data) {
        throw new HttpsError("not-found", "Community missing");
      }
      const count = typeof data.memberCount === "number" ? data.memberCount : 0;
      if (count >= MAX_COMMUNITY_MEMBERS) {
        throw new HttpsError("failed-precondition", "Community is full");
      }
      const memberSnap = await t.get(membershipRef);
      if (memberSnap.exists) {
        throw new HttpsError("already-exists", "Already a member");
      }
      const now = admin.firestore.FieldValue.serverTimestamp();
      t.update(communityRef, {
        memberCount: count + 1,
        updatedAt: now,
      });
      t.set(membershipRef, {
        id: membershipId,
        communityId,
        profileId: uid,
        displayName,
        profilePhotoUrl,
        joinedAt: now,
        communityOdds: 0,
        communityGamesPlayed: 0,
        createdAt: now,
        updatedAt: now,
      });
    });
  } catch (e) {
    if (e instanceof HttpsError) {
      throw e;
    }
    logger.error("joinCommunity transaction failed", e);
    throw new HttpsError("internal", "Could not join community");
  }

  return newEnvelope({communityId});
});

export const previewJoinCommunity = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }

  const raw = request.data?.inviteCode;
  const inviteCode = typeof raw === "string" ? raw.trim().toUpperCase() : "";
  if (!inviteCode) {
    throw new HttpsError("invalid-argument", "inviteCode is required");
  }

  const communities = await db.collection("communities")
    .where("inviteCode", "==", inviteCode)
    .limit(1)
    .get();

  if (communities.empty) {
    throw new HttpsError("not-found", "Invalid invite code");
  }

  const communityRef = communities.docs[0].ref;
  const communityId = communityRef.id;
  const data = communities.docs[0].data();

  const name = typeof data.name === "string" ? data.name : "Community";
  let memberCount = typeof data.memberCount === "number" ? data.memberCount : 0;

  // Older docs might omit memberCount. Fallback to counting memberships if needed.
  if (typeof data.memberCount !== "number") {
    const membershipsSnap = await db.collection("memberships")
      .where("communityId", "==", communityId)
      .get();
    memberCount = membershipsSnap.size;
  }

  if (memberCount >= MAX_COMMUNITY_MEMBERS) {
    throw new HttpsError("failed-precondition", "Community is full");
  }

  return newEnvelope({communityId, name, memberCount});
});
