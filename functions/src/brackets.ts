import * as admin from "firebase-admin";
import {HttpsError, onCall, type CallableRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  isValidSeedMethod,
  validateRoundsStructure,
  validateRoundOneCoversParticipants,
  type BracketRound,
} from "./bracketModel.js";
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
 * Reads `profileId` from membership document data (string or legacy int).
 * @param {Record<string, unknown>} data Raw membership fields.
 * @return {?string} Non-empty profile id or null.
 */
export function extractProfileIdFromMembershipData(
  data: Record<string, unknown>
): string | null {
  const raw = data["profileId"];
  if (typeof raw === "string") {
    const t = raw.trim();
    return t.length > 0 ? t : null;
  }
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const s = String(Math.trunc(raw));
    return s.length > 0 ? s : null;
  }
  return null;
}

const BUILTIN_BRACKET_GAME_TYPES = new Set([
  "PONG",
  "BEER_BALL",
  "BATTLE_PONG",
  "BASEBALL",
  "CROSSFIRE",
]);

/**
 * Normalizes callable `gameType` to a built-in code or `CUSTOM`.
 * Unknown strings default to `PONG`.
 * @param {unknown} raw Request field `gameType`.
 * @return {string} Stored `brackets.gameType` value.
 */
export function parseBracketGameType(raw: unknown): string {
  if (typeof raw !== "string") {
    return "PONG";
  }
  const t = raw.trim();
  if (t === "CUSTOM") {
    return "CUSTOM";
  }
  if (BUILTIN_BRACKET_GAME_TYPES.has(t)) {
    return t;
  }
  return "PONG";
}

/** Callable `teamSize`: max players per team (chunking uses a short last team when N is not divisible). */
export const BRACKET_TEAM_SIZE_MAX = 20;

/**
 * Parses and validates teamSize from request data.
 * Integer 1–{@link BRACKET_TEAM_SIZE_MAX} (inclusive).
 * @param {unknown} raw Raw value from request.
 * @return {number} Validated teamSize.
 */
export function parseBracketCallableTeamSize(raw: unknown): number {
  const n = typeof raw === "number" ? raw : Number(raw);
  if (!Number.isInteger(n) || n < 1 || n > BRACKET_TEAM_SIZE_MAX) {
    throw new HttpsError(
      "invalid-argument",
      `teamSize must be an integer between 1 and ${BRACKET_TEAM_SIZE_MAX}`
    );
  }
  return n;
}

/**
 * Creates a league bracket (odds / random / manual seed path).
 * Last team may have fewer than `teamSize` players when member count is not divisible.
 */
async function runCreateBracket(request: CallableRequest) {
  logger.info("runCreateBracket: entry", {
    impl: "v2-uneven-last-team-ok",
    uid: request.auth?.uid,
  });

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

  const teamSize = parseBracketCallableTeamSize(request.data?.teamSize);
  const gameType = parseBracketGameType(request.data?.gameType);

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

  const rawIds: string[] = [];
  let skippedMembershipsMissingProfileId = 0;
  for (const doc of membershipsSnap.docs) {
    const data = doc.data() as Record<string, unknown>;
    const id = extractProfileIdFromMembershipData(data);
    if (id) {
      rawIds.push(id);
    } else {
      skippedMembershipsMissingProfileId += 1;
      logger.warn("runCreateBracket: membership skipped (no profileId)", {
        communityId,
        membershipDocId: doc.id,
      });
    }
  }

  const participantProfileIds = sortUniqueProfileIds(rawIds);
  if (skippedMembershipsMissingProfileId > 0) {
    logger.warn("runCreateBracket: memberships without usable profileId", {
      communityId,
      skippedMembershipsMissingProfileId,
      membershipDocsRead: membershipsSnap.docs.length,
    });
  }

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

  let customGameDefinitionId: string | undefined;
  let customGameDefinitionName: string | undefined;
  if (gameType === "CUSTOM") {
    const rawCustomId = request.data?.customGameDefinitionId;
    const customId =
      typeof rawCustomId === "string" ? rawCustomId.trim() : "";
    if (!customId) {
      throw new HttpsError(
        "invalid-argument",
        "customGameDefinitionId is required when gameType is CUSTOM"
      );
    }
    const defSnap = await db
      .collection("communities")
      .doc(communityId)
      .collection("gameDefinitions")
      .doc(customId)
      .get();
    if (!defSnap.exists) {
      throw new HttpsError("not-found", "Game definition not found");
    }
    const defName = defSnap.data()?.["name"];
    if (typeof defName !== "string" || !defName.trim()) {
      throw new HttpsError("internal", "Invalid game definition");
    }
    customGameDefinitionId = customId;
    customGameDefinitionName = defName.trim();
  }

  logger.info("createBracket: participants resolved", {
    communityId,
    participantCount,
    teamCount,
    seedMethod,
    teamSize,
    gameType,
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
      const rosterCheck = validateRoundOneCoversParticipants(
        generated as BracketRound[],
        participantProfileIds
      );
      if (!rosterCheck.valid) {
        logger.error("createBracket: round1 does not cover all participants", {
          bracketId,
          errors: rosterCheck.errors,
          participantCount: participantProfileIds.length,
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
      const rosterCheck = validateRoundOneCoversParticipants(
        generated as BracketRound[],
        participantProfileIds
      );
      if (!rosterCheck.valid) {
        logger.error("createBracket: RANDOM round1 roster mismatch", {
          bracketId,
          errors: rosterCheck.errors,
          participantCount: participantProfileIds.length,
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
    const bracketDoc: Record<string, unknown> = {
      id: bracketId,
      communityId,
      participantProfileIds,
      seedMethod,
      teamSize,
      gameType,
      status,
      rounds,
      createdAt: now,
      updatedAt: now,
    };
    if (gameType === "CUSTOM" && customGameDefinitionId) {
      bracketDoc.customGameDefinitionId = customGameDefinitionId;
      bracketDoc.customGameDefinitionName = customGameDefinitionName;
    }
    await bracketRef.set(bracketDoc);
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
}

/**
 * **Preferred callable name for new clients.** Some Firebase projects still have a legacy
 * Gen1 `createBracket` deployed; the iOS app calls this name so it always hits this Gen2 implementation.
 */
export const createLeagueBracket = onCall({region}, runCreateBracket);

/** @deprecated Prefer routing clients to {@link createLeagueBracket} to avoid Gen1 name collisions. */
export const createBracket = onCall({region}, runCreateBracket);
