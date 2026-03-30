import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {isValidSeedMethod, validateRoundsStructure} from "./bracketModel.js";
import {buildCommunityOddsRounds} from "./bracketSeeding.js";
import {buildRandomSeededRounds} from "./bracketRandomSeed.js";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const region = "us-central1";

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

/**
 * Deduplicates and sorts profile IDs lexicographically
 * for a stable participant snapshot.
 * @param {string[]} ids Raw profile ID array.
 * @return {string[]} Sorted unique IDs.
 */
export function sortUniqueProfileIds(ids: string[]): string[] {
  return [...new Set(ids)].sort();
}

/**
 * Parses and validates teamSize from request data.
 * Must be integer 1–4.
 * @param {unknown} raw Raw value from request.
 * @return {number} Validated teamSize.
 */
function parseTeamSize(raw: unknown): number {
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > 4) {
    throw new HttpsError(
      "invalid-argument",
      "teamSize must be an integer between 1 and 4"
    );
  }
  return n;
}

export const createBracket = onCall({region}, async (request) => {
  // 1. Auth
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const uid = request.auth.uid;

  // 2. Input validation
  const communityId =
    typeof request.data?.communityId === "string" ?
      request.data.communityId.trim() :
      "";
  if (!communityId) {
    throw new HttpsError(
      "invalid-argument",
      "communityId is required"
    );
  }

  const seedMethod = request.data?.seedMethod;
  if (!isValidSeedMethod(seedMethod)) {
    throw new HttpsError(
      "invalid-argument",
      "seedMethod must be COMMUNITY_ODDS, MANUAL, or RANDOM"
    );
  }

  const teamSize = parseTeamSize(request.data?.teamSize);

  // 3. Authorization — caller must be a member
  const membershipId = `${communityId}_${uid}`;
  const membershipSnap = await db
    .collection("memberships")
    .doc(membershipId)
    .get();
  if (!membershipSnap.exists) {
    throw new HttpsError(
      "permission-denied",
      "You are not a member of this community"
    );
  }

  // 4. Collect all participants from memberships
  const membershipsSnap = await db
    .collection("memberships")
    .where("communityId", "==", communityId)
    .get();

  const rawIds: string[] = membershipsSnap.docs
    .map((doc) => doc.data()["profileId"])
    .filter((id): id is string => typeof id === "string");

  const participantProfileIds = sortUniqueProfileIds(rawIds);

  const participantCount = participantProfileIds.length;
  if (participantCount < 2) {
    throw new HttpsError(
      "invalid-argument",
      "Community must have at least 2 members to create a bracket"
    );
  }

  // 5. Need at least two teams when chunking by teamSize (last team may be short / uneven).
  const teamCount = Math.ceil(participantCount / teamSize);
  if (teamCount < 2) {
    throw new HttpsError(
      "invalid-argument",
      `Not enough members for two teams at team size ${teamSize} (${participantCount} members). Try a smaller team size or add more members.`
    );
  }

  logger.info("createBracket: participants resolved", {
    communityId,
    participantCount,
    teamCount,
    seedMethod,
    teamSize,
  });

  // 6. Build rounds: COMMUNITY_ODDS (odds), RANDOM (deterministic shuffle),
  // MANUAL stays empty until finalizeManualBracket.
  const bracketRef = db.collection("brackets").doc();
  const bracketId = bracketRef.id;

  let rounds: unknown[] = [];

  if (seedMethod === "COMMUNITY_ODDS") {
    try {
      const generated = await buildCommunityOddsRounds(
        bracketId,
        participantProfileIds,
        communityId,
        teamSize
      );
      const validation = validateRoundsStructure(generated);
      if (!validation.valid) {
        logger.error("createBracket: invalid rounds generated", {
          bracketId,
          errors: validation.errors,
        });
        throw new HttpsError(
          "internal",
          "Could not generate valid bracket rounds"
        );
      }
      rounds = generated;
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("createBracket: seeding failed", e);
      throw new HttpsError(
        "internal",
        "Could not seed bracket"
      );
    }
  } else if (seedMethod === "RANDOM") {
    try {
      const generated = buildRandomSeededRounds(
        bracketId,
        participantProfileIds,
        teamSize
      );
      const validation = validateRoundsStructure(generated);
      if (!validation.valid) {
        logger.error("createBracket: invalid RANDOM rounds", {
          bracketId,
          errors: validation.errors,
        });
        throw new HttpsError(
          "internal",
          "Could not generate valid bracket rounds"
        );
      }
      rounds = generated;
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      logger.error("createBracket: RANDOM seeding failed", e);
      throw new HttpsError(
        "internal",
        "Could not seed bracket"
      );
    }
  }

  // 7. Write bracket document
  const now = admin.firestore.FieldValue.serverTimestamp();
  const status = seedMethod === "MANUAL" ? "DRAFT" : "ACTIVE";

  try {
    await bracketRef.set({
      id: bracketId,
      communityId,
      participantProfileIds,
      seedMethod,
      teamSize,
      status,
      rounds,
      createdAt: now,
      updatedAt: now,
    });
  } catch (e) {
    logger.error("createBracket: Firestore write failed", e);
    throw new HttpsError("internal", "Could not create bracket");
  }

  logger.info("createBracket: bracket created", {
    participantCount,
    bracketId,
    communityId,
    teamSize,
    status,
    roundCount: (rounds as unknown[]).length,
  });

  return newEnvelope({bracketId});
});
