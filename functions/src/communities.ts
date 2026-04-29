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

function normalizeGameDefinitionName(input: unknown): string {
  if (typeof input !== "string") {
    return "";
  }
  return input.trim();
}

function normalizeGameDefinitionRules(input: unknown): string | null {
  if (input === null || input === undefined) {
    return null;
  }
  if (typeof input !== "string") {
    return null;
  }
  const trimmed = input.trim();
  return trimmed.length ? trimmed : null;
}

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
        hiddenFromMembers: false,
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
      const hidden = data.hiddenFromMembers === true;
      const createdBy = data.createdByProfileId as string | undefined;
      if (hidden && createdBy !== uid) {
        throw new HttpsError("not-found", "Invalid invite code");
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
  const hidden = data.hiddenFromMembers === true;
  const createdBy = data.createdByProfileId as string | undefined;
  if (hidden && createdBy !== request.auth.uid) {
    throw new HttpsError("not-found", "Invalid invite code");
  }

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

/**
 * Creator-only: hide or unhide a league from members (does not delete data).
 * Denormalizes `leagueHiddenForMember` onto non-creator memberships for rules.
 */
export const setCommunityHidden = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const rawId = request.data?.communityId;
  const communityId = typeof rawId === "string" ? rawId.trim() : "";
  if (!communityId) {
    throw new HttpsError("invalid-argument", "communityId is required");
  }
  if (typeof request.data?.hidden !== "boolean") {
    throw new HttpsError("invalid-argument", "hidden must be a boolean");
  }
  const hidden = request.data.hidden as boolean;
  const uid = request.auth.uid;
  const communityRef = db.collection("communities").doc(communityId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  try {
    await db.runTransaction(async (t) => {
      const commSnap = await t.get(communityRef);
      const comm = commSnap.data();
      if (!comm) {
        throw new HttpsError("not-found", "Community not found");
      }
      if (comm.createdByProfileId !== uid) {
        throw new HttpsError("permission-denied", "Only the league creator can hide or unhide");
      }

      const memQuery = db.collection("memberships")
        .where("communityId", "==", communityId);
      const memSnap = await t.get(memQuery);

      t.update(communityRef, {
        hiddenFromMembers: hidden,
        updatedAt: now,
      });

      for (const doc of memSnap.docs) {
        const profileId = doc.data().profileId as string | undefined;
        if (!profileId) {
          continue;
        }
        if (hidden) {
          if (profileId === uid) {
            t.update(doc.ref, {
              leagueHiddenForMember: admin.firestore.FieldValue.delete(),
              updatedAt: now,
            });
          } else {
            t.update(doc.ref, {
              leagueHiddenForMember: true,
              updatedAt: now,
            });
          }
        } else {
          t.update(doc.ref, {
            leagueHiddenForMember: admin.firestore.FieldValue.delete(),
            updatedAt: now,
          });
        }
      }
    });
  } catch (e) {
    if (e instanceof HttpsError) {
      throw e;
    }
    logger.error("setCommunityHidden failed", e);
    throw new HttpsError("internal", "Could not update league visibility");
  }

  return newEnvelope({communityId, hidden});
});

/**
 * League members may list/manage custom game definitions; creators of hidden leagues
 * retain access. Matches `listGameDefinitions` / CRUD callables.
 * @param {admin.firestore.DocumentData|undefined} comm Community document data.
 * @param {boolean} membershipExists Whether `memberships/{communityId}_{uid}` exists.
 * @param {string} uid Caller uid.
 */
function assertMemberCanManageGameDefinitions(
  comm: admin.firestore.DocumentData | undefined,
  membershipExists: boolean,
  uid: string
): void {
  if (!comm) {
    throw new HttpsError("not-found", "Community not found");
  }
  if (!membershipExists) {
    throw new HttpsError("permission-denied", "Community member required");
  }
  const hidden = comm.hiddenFromMembers === true;
  const createdBy = typeof comm.createdByProfileId === "string" ? comm.createdByProfileId : "";
  const blockedByHidden = hidden && createdBy !== uid;
  if (blockedByHidden) {
    throw new HttpsError("permission-denied", "Community member required");
  }
}

/**
 * Lists game definitions for a league (`communities/{communityId}/gameDefinitions/*`).
 * Member read access mirrors league board visibility behavior.
 */
export const listGameDefinitions = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const communityId = typeof request.data?.communityId === "string" ?
    request.data.communityId.trim() :
    "";
  if (!communityId) {
    throw new HttpsError("invalid-argument", "communityId is required");
  }

  const uid = request.auth.uid;
  const membershipRef = db.collection("memberships").doc(`${communityId}_${uid}`);
  const communityRef = db.collection("communities").doc(communityId);
  const [membershipSnap, communitySnap] = await Promise.all([
    membershipRef.get(),
    communityRef.get(),
  ]);
  const c = communitySnap.data();
  assertMemberCanManageGameDefinitions(c, membershipSnap.exists, uid);

  const defsSnap = await communityRef.collection("gameDefinitions")
    .orderBy("createdAt", "desc")
    .get();
  const items = defsSnap.docs.map((d) => {
    const v = d.data();
    return {
      gameDefinitionId: d.id,
      name: typeof v.name === "string" ? v.name : "",
      rulesText: typeof v.rulesText === "string" ? v.rulesText : "",
      createdByProfileId:
        typeof v.createdByProfileId === "string" ? v.createdByProfileId : "",
      createdAtMillis:
        v.createdAt instanceof admin.firestore.Timestamp ?
          v.createdAt.toMillis() :
          0,
      updatedAtMillis:
        v.updatedAt instanceof admin.firestore.Timestamp ?
          v.updatedAt.toMillis() :
          0,
    };
  });

  return newEnvelope({items});
});

/**
 * League members: add a custom game definition under a community.
 */
export const createGameDefinition = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const communityId = typeof request.data?.communityId === "string" ?
    request.data.communityId.trim() :
    "";
  const name = normalizeGameDefinitionName(request.data?.name);
  const rulesText = normalizeGameDefinitionRules(request.data?.rulesText);
  if (!communityId) {
    throw new HttpsError("invalid-argument", "communityId is required");
  }
  if (!name) {
    throw new HttpsError("invalid-argument", "name is required");
  }
  if (name.length > 80) {
    throw new HttpsError("invalid-argument", "name must be <= 80 chars");
  }
  if (rulesText && rulesText.length > 8000) {
    throw new HttpsError("invalid-argument", "rulesText must be <= 8000 chars");
  }

  const uid = request.auth.uid;
  const communityRef = db.collection("communities").doc(communityId);
  const defRef = communityRef.collection("gameDefinitions").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();

  const membershipRef = db.collection("memberships").doc(`${communityId}_${uid}`);
  await db.runTransaction(async (t) => {
    const [commSnap, membershipSnap] = await Promise.all([
      t.get(communityRef),
      t.get(membershipRef),
    ]);
    assertMemberCanManageGameDefinitions(commSnap.data(), membershipSnap.exists, uid);
    t.set(defRef, {
      id: defRef.id,
      communityId,
      name,
      rulesText: rulesText ?? null,
      createdByProfileId: uid,
      createdAt: now,
      updatedAt: now,
    });
  });

  return newEnvelope({gameDefinitionId: defRef.id});
});

/**
 * League members: update custom game definition metadata.
 */
export const updateGameDefinition = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const communityId = typeof request.data?.communityId === "string" ?
    request.data.communityId.trim() :
    "";
  const gameDefinitionId = typeof request.data?.gameDefinitionId === "string" ?
    request.data.gameDefinitionId.trim() :
    "";
  const name = normalizeGameDefinitionName(request.data?.name);
  const rulesText = normalizeGameDefinitionRules(request.data?.rulesText);
  if (!communityId || !gameDefinitionId) {
    throw new HttpsError("invalid-argument", "communityId and gameDefinitionId are required");
  }
  if (!name) {
    throw new HttpsError("invalid-argument", "name is required");
  }
  if (name.length > 80) {
    throw new HttpsError("invalid-argument", "name must be <= 80 chars");
  }
  if (rulesText && rulesText.length > 8000) {
    throw new HttpsError("invalid-argument", "rulesText must be <= 8000 chars");
  }

  const uid = request.auth.uid;
  const communityRef = db.collection("communities").doc(communityId);
  const defRef = communityRef.collection("gameDefinitions").doc(gameDefinitionId);
  const now = admin.firestore.FieldValue.serverTimestamp();

  const membershipRef = db.collection("memberships").doc(`${communityId}_${uid}`);
  await db.runTransaction(async (t) => {
    const [commSnap, membershipSnap, defSnap] = await Promise.all([
      t.get(communityRef),
      t.get(membershipRef),
      t.get(defRef),
    ]);
    assertMemberCanManageGameDefinitions(commSnap.data(), membershipSnap.exists, uid);
    if (!defSnap.exists) {
      throw new HttpsError("not-found", "Game definition not found");
    }
    t.update(defRef, {
      name,
      rulesText: rulesText ?? null,
      updatedAt: now,
    });
  });

  return newEnvelope({gameDefinitionId});
});

/**
 * League members: delete a custom game definition.
 */
export const deleteGameDefinition = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const communityId = typeof request.data?.communityId === "string" ?
    request.data.communityId.trim() :
    "";
  const gameDefinitionId = typeof request.data?.gameDefinitionId === "string" ?
    request.data.gameDefinitionId.trim() :
    "";
  if (!communityId || !gameDefinitionId) {
    throw new HttpsError("invalid-argument", "communityId and gameDefinitionId are required");
  }

  const uid = request.auth.uid;
  const communityRef = db.collection("communities").doc(communityId);
  const defRef = communityRef.collection("gameDefinitions").doc(gameDefinitionId);

  const membershipRef = db.collection("memberships").doc(`${communityId}_${uid}`);
  await db.runTransaction(async (t) => {
    const [commSnap, membershipSnap, defSnap] = await Promise.all([
      t.get(communityRef),
      t.get(membershipRef),
      t.get(defRef),
    ]);
    assertMemberCanManageGameDefinitions(commSnap.data(), membershipSnap.exists, uid);
    if (!defSnap.exists) {
      throw new HttpsError("not-found", "Game definition not found");
    }
    t.delete(defRef);
  });

  return newEnvelope({gameDefinitionId});
});
