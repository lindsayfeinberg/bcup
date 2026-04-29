import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  validateRoundsStructure,
  validateRoundOneCoversParticipants,
  type BracketMatch,
  type BracketRound,
} from "./bracketModel.js";
import {generateBracketRounds} from "./bracketSeeding.js";

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
 * Validates that orderedIds is a permutation of expectedIds.
 * Same length, no duplicates, same multiset of values.
 * @param {string[]} orderedIds User-supplied seed order.
 * @param {string[]} expectedIds Bracket participantProfileIds.
 * @return {string | null} Error message or null if valid.
 */
export function validatePermutation(
  orderedIds: string[],
  expectedIds: string[]
): string | null {
  if (orderedIds.length !== expectedIds.length) {
    return (
      `Expected ${expectedIds.length} ids, ` +
      `got ${orderedIds.length}`
    );
  }
  const seen = new Set<string>();
  for (const id of orderedIds) {
    if (seen.has(id)) {
      return `Duplicate profileId: ${id}`;
    }
    seen.add(id);
  }
  const expectedSet = new Set(expectedIds);
  for (const id of orderedIds) {
    if (!expectedSet.has(id)) {
      return `Unknown profileId: ${id}`;
    }
  }
  return null;
}

/**
 * Greedy team sizes matching chunkIntoTeams: full rows first,
 * last row may be short.
 * @param {number} participantCount Total players.
 * @param {number} teamSize Players per side.
 * @return {Array<number>} Length of each team row in bracket order.
 */
export function expectedTeamSizes(
  participantCount: number,
  teamSize: number
): number[] {
  const sizes: number[] = [];
  let remaining = participantCount;
  while (remaining > 0) {
    const n = Math.min(teamSize, remaining);
    sizes.push(n);
    remaining -= n;
  }
  return sizes;
}

/**
 * Validates manual team rows: partition matches expectedTeamSizes;
 * row-major flatten is a permutation of participants.
 * @param {Array<Array<string>>} teams Ordered teams (seed order).
 * @param {Array<string>} participantProfileIds Bracket snapshot.
 * @param {number} teamSize Players per side from bracket doc.
 * @return {?string} Error message or null if valid.
 */
export function validateManualTeams(
  teams: string[][],
  participantProfileIds: string[],
  teamSize: number
): string | null {
  if (!Array.isArray(teams) || teams.length === 0) {
    return "teams must be a non-empty array";
  }
  if (
    !teams.every(
      (row) =>
        Array.isArray(row) &&
        row.length > 0 &&
        row.every((id) => typeof id === "string" && id.length > 0)
    )
  ) {
    return "each team must be a non-empty array of non-empty strings";
  }
  const expected = expectedTeamSizes(participantProfileIds.length, teamSize);
  if (teams.length !== expected.length) {
    return (
      `Expected ${expected.length} teams, got ${teams.length}`
    );
  }
  for (let i = 0; i < teams.length; i++) {
    if (teams[i].length !== expected[i]) {
      return (
        `Team ${i + 1} must have ${expected[i]} players, ` +
        `got ${teams[i].length}`
      );
    }
  }
  const flat = teams.flat();
  return validatePermutation(flat, participantProfileIds);
}

/**
 * Builds bracket rounds from explicit team rosters (bracket order).
 * @param {string} bracketId Parent bracket ID for matchIds.
 * @param {Array<Array<string>>} teams Ordered teams, best seed first.
 * @return {Array<Object>} Generated bracket rounds.
 */
export function buildManualRoundsFromTeams(
  bracketId: string,
  teams: string[][]
) {
  return generateBracketRounds(bracketId, teams);
}

export const finalizeManualBracket = onCall(
  {region},
  async (request) => {
    // 1. Auth
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;

    // 2. Input validation
    const bracketId =
      typeof request.data?.bracketId === "string" ?
        request.data.bracketId.trim() :
        "";
    if (!bracketId) {
      throw new HttpsError(
        "invalid-argument",
        "bracketId is required"
      );
    }

    const rawTeams = request.data?.teams;
    if (
      !Array.isArray(rawTeams) ||
      rawTeams.length === 0 ||
      !rawTeams.every(
        (row) =>
          Array.isArray(row) &&
          row.length > 0 &&
          row.every((id) => typeof id === "string")
      )
    ) {
      throw new HttpsError(
        "invalid-argument",
        "teams must be a non-empty array of non-empty string arrays"
      );
    }
    const teams = rawTeams as string[][];

    // 3. Load bracket
    const bracketSnap = await db
      .collection("brackets")
      .doc(bracketId)
      .get();

    if (!bracketSnap.exists) {
      throw new HttpsError(
        "not-found",
        "Bracket not found"
      );
    }

    const bracket = bracketSnap.data() as Record<string, unknown>;

    // 4. Require MANUAL + DRAFT + empty rounds
    if (bracket["seedMethod"] !== "MANUAL") {
      throw new HttpsError(
        "invalid-argument",
        "Bracket seedMethod must be MANUAL"
      );
    }
    if (bracket["status"] !== "DRAFT") {
      throw new HttpsError(
        "invalid-argument",
        "Bracket is already finalized"
      );
    }
    const existingRounds = bracket["rounds"] as unknown[];
    if (Array.isArray(existingRounds) && existingRounds.length > 0) {
      throw new HttpsError(
        "invalid-argument",
        "Bracket rounds are already set"
      );
    }

    // 5. Auth — caller must be a member of the community
    const communityId = bracket["communityId"] as string;
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

    // 6. Validate team partition + permutation
    const participantProfileIds =
      bracket["participantProfileIds"] as string[];
    const teamSize = bracket["teamSize"] as number;
    const teamsError = validateManualTeams(
      teams,
      participantProfileIds,
      teamSize
    );
    if (teamsError) {
      throw new HttpsError(
        "invalid-argument",
        `Invalid teams: ${teamsError}`
      );
    }

    // 7. Build rounds
    const rounds = buildManualRoundsFromTeams(bracketId, teams);

    logger.info("finalizeManualBracket: built rounds", {
      bracketId,
      round1MatchCount: rounds[0]?.matches?.length,
      round1MatchIds: rounds[0]?.matches?.map(
        (m: BracketMatch) => m.matchId
      ),
    });

    // 8. Validate rounds
    const validation = validateRoundsStructure(rounds);
    if (!validation.valid) {
      logger.error("finalizeManualBracket: invalid rounds", {
        bracketId,
        errors: validation.errors,
      });
      throw new HttpsError(
        "internal",
        "Could not generate valid bracket rounds"
      );
    }
    const rosterCheck = validateRoundOneCoversParticipants(
      rounds as BracketRound[],
      participantProfileIds
    );
    if (!rosterCheck.valid) {
      logger.error("finalizeManualBracket: round1 roster mismatch", {
        bracketId,
        errors: rosterCheck.errors,
      });
      throw new HttpsError(
        "internal",
        "Could not generate valid bracket rounds"
      );
    }

    // 9. Update bracket
    const now = admin.firestore.FieldValue.serverTimestamp();
    try {
      logger.info("finalizeManualBracket: rounds to write", {
        bracketId,
        roundsJSON: JSON.stringify(rounds),
      });
      await bracketSnap.ref.update({
        rounds,
        status: "ACTIVE",
        updatedAt: now,
      });
    } catch (e) {
      logger.error("finalizeManualBracket: update failed", e);
      throw new HttpsError(
        "internal",
        "Could not finalize bracket"
      );
    }

    logger.info("finalizeManualBracket: complete", {
      bracketId,
      communityId,
      roundCount: rounds.length,
    });

    return newEnvelope({});
  }
);
