import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import type {
  BracketDocument,
  BracketMatch,
} from "./bracketModel.js";

// Match validation lives in bracketModel.ts, but we keep some additional
// invariants local to this file (e.g. "winners+losers partition match").
import {validateBracketMatch} from "./bracketModel.js";

const db = admin.firestore();
const region = "us-central1";

function newEnvelope<T extends Record<string, unknown>>(data: T) {
  const suffix = Math.random().toString(36).slice(2, 9);
  return {
    ok: true,
    apiVersion: "v1",
    data,
    meta: {requestId: `req_${Date.now()}_${suffix}`},
  };
}

function hasOutcomeKeys(match: BracketMatch): boolean {
  const hasWinner =
    Object.prototype.hasOwnProperty.call(match, "winnerProfileIds") &&
    Array.isArray(match.winnerProfileIds) &&
    match.winnerProfileIds.length > 0;
  const hasLoser =
    Object.prototype.hasOwnProperty.call(match, "loserProfileIds") &&
    Array.isArray(match.loserProfileIds) &&
    match.loserProfileIds.length > 0;

  // Bye matches may be finalized with only a winner side (no loser keys).
  return hasWinner || hasLoser;
}

function isPlaceholderMatch(match: BracketMatch): boolean {
  return Object.prototype.hasOwnProperty.call(match, "feederMatchIds");
}

function setEq(a: string[], b: string[]): boolean {
  if (a.length !== b.length) return false;
  const s1 = new Set(a);
  const s2 = new Set(b);
  if (s1.size !== s2.size) return false;
  for (const v of s1) {
    if (!s2.has(v)) return false;
  }
  return true;
}

function arrayNoOverlap(a: string[], b: string[]): boolean {
  const bs = new Set(b);
  for (const v of a) {
    if (bs.has(v)) return false;
  }
  return true;
}

function findMatch(
  bracket: BracketDocument,
  matchId: string
):
  | {roundNumber: number; match: BracketMatch; rIdx: number; mIdx: number}
  | null {
  for (let rIdx = 0; rIdx < bracket.rounds.length; rIdx++) {
    const round = bracket.rounds[rIdx];
    for (let mIdx = 0; mIdx < round.matches.length; mIdx++) {
      const match = round.matches[mIdx];
      if (match.matchId === matchId) {
        return {roundNumber: round.roundNumber, match, rIdx, mIdx};
      }
    }
  }
  return null;
}

function deepCloneBracketDoc(bracket: BracketDocument): BracketDocument {
  return {
    ...bracket,
    rounds: bracket.rounds.map((r) => ({
      ...r,
      matches: r.matches.map((m) => ({
        ...m,
        // Ensure optional arrays are cloned too (if present).
        ...(m.winnerProfileIds ? {winnerProfileIds: [...m.winnerProfileIds]} : {}),
        ...(m.loserProfileIds ? {loserProfileIds: [...m.loserProfileIds]} : {}),
        ...(m.feederMatchIds ? {feederMatchIds: [...m.feederMatchIds]} : {}),
        participantProfileIds: [...m.participantProfileIds],
      })),
    })),
  };
}

export interface BracketOutcomeInput {
  bracketId: string;
  bracketMatchId: string;
  communityId: string;
  participantProfileIds: string[];
  winnerProfileIds: string[];
  loserProfileIds: string[];
}

export interface ApplyBracketOutcomeResult {
  didUpdate: boolean;
}

/**
 * Pure core: apply a game log outcome to a bracket document in memory.
 *
 * Rules:
 * - If the target match already has outcome keys, it is a no-op.
 * - If the target match is a placeholder (has feederMatchIds), it is rejected.
 * - winners/losers must partition the referenced match's participantProfileIds.
 * - On successful match outcome write, advance any placeholder matches whose
 *   both feeder matches are now played.
 * - Set bracket COMPLETE only when the final match has outcome.
 */
export function applyGameLogOutcomeToBracketDoc(
  bracket: BracketDocument,
  input: Omit<BracketOutcomeInput, "bracketId">
): {updatedBracket: BracketDocument; result: ApplyBracketOutcomeResult} {
  const target = findMatch(bracket, input.bracketMatchId);
  if (!target) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  const targetMatch = target.match;

  // Idempotent skip.
  if (hasOutcomeKeys(targetMatch)) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  // Reject placeholder outcomes (round2+ placeholders need participantProfileIds first).
  if (isPlaceholderMatch(targetMatch)) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  // Basic community gating is done in the Firestore-trigger wrapper, but keep
  // it here too so the pure function can be unit-tested.
  if (bracket.communityId !== input.communityId) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }
  if (bracket.status !== "ACTIVE") {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  // Validate winners/losers partition exactly the bracket match participants.
  const matchParticipants = targetMatch.participantProfileIds;
  const unionWinnerLoser = [...input.winnerProfileIds, ...input.loserProfileIds];
  const matchParticipantSet = new Set(matchParticipants);
  const winnerSet = new Set(input.winnerProfileIds);
  const loserSet = new Set(input.loserProfileIds);

  const winnersSubset = input.winnerProfileIds.every((id) =>
    matchParticipantSet.has(id)
  );
  const losersSubset = input.loserProfileIds.every((id) =>
    matchParticipantSet.has(id)
  );

  const disjoint = arrayNoOverlap(input.winnerProfileIds, input.loserProfileIds);
  const participantsPartitionMatch =
    new Set(unionWinnerLoser).size === matchParticipantSet.size &&
    [...new Set(unionWinnerLoser)].every((id) => matchParticipantSet.has(id));
  const logParticipantsPartition = setEq(
    input.participantProfileIds.slice().sort(),
    [...winnerSet, ...loserSet].sort()
  );

  if (!winnersSubset || !losersSubset || !disjoint || !participantsPartitionMatch) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }
  // Keep this validation strict to match T10.7.c.
  if (!logParticipantsPartition) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  // Deep clone and mutate only what we need.
  const updated = deepCloneBracketDoc(bracket);
  const updatedTargetMatch = updated.rounds[target.rIdx].matches[target.mIdx];

  // Ensure the match object would still be valid per bracketModel.
  const candidateMatch = {
    ...updatedTargetMatch,
    winnerProfileIds: input.winnerProfileIds,
    loserProfileIds: input.loserProfileIds,
  };
  const validation = validateBracketMatch(candidateMatch);
  if (!validation.valid) {
    return {updatedBracket: bracket, result: {didUpdate: false}};
  }

  updatedTargetMatch.winnerProfileIds = input.winnerProfileIds;
  updatedTargetMatch.loserProfileIds = input.loserProfileIds;

  // Advance placeholders using feederMatchIds.
  for (const round of updated.rounds) {
    for (const match of round.matches) {
      if (!isPlaceholderMatch(match)) continue;
      const feederIds = match.feederMatchIds ?? [];
      if (feederIds.length !== 2) continue;

      const feederA = findMatch(updated, feederIds[0]);
      const feederB = findMatch(updated, feederIds[1]);

      const feederAWinner =
        feederA && hasOutcomeKeys(feederA.match)
          ? feederA.match.winnerProfileIds ?? []
          : [];
      const feederBWinner =
        feederB && hasOutcomeKeys(feederB.match)
          ? feederB.match.winnerProfileIds ?? []
          : [];

      // Nothing new learned from feeder outcomes.
      if (feederAWinner.length === 0 && feederBWinner.length === 0) continue;

      // Merge any prefilled participants (e.g. from byes) with newly known winners.
      const combined = [
        ...(match.participantProfileIds ?? []),
        ...feederAWinner,
        ...feederBWinner,
      ];
      match.participantProfileIds = [...new Set(combined)];

      const bothFeedersPlayed =
        feederAWinner.length > 0 && feederBWinner.length > 0;

      const fullParticipantSetKnown =
        match.participantProfileIds.length === bracket.teamSize * 2;

      // Convert placeholder -> scheduled match once both feeder sides are determined.
      if (bothFeedersPlayed || fullParticipantSetKnown) {
        delete (match as BracketMatch).feederMatchIds;

        // Prefer the deterministic full set when both feeders played.
        if (bothFeedersPlayed) {
          match.participantProfileIds = [
            ...feederAWinner,
            ...feederBWinner,
          ];
        }
      }
    }
  }

  // Complete if the final match now has outcome.
  const maxRoundNumber = Math.max(...updated.rounds.map((r) => r.roundNumber));
  const finalMatches = updated.rounds.flatMap((r) =>
    r.roundNumber === maxRoundNumber ? r.matches : []
  );
  if (finalMatches.length === 1 && hasOutcomeKeys(finalMatches[0])) {
    updated.status = "COMPLETE";
  }

  return {updatedBracket: updated, result: {didUpdate: true}};
}

/**
 * Firestore-trigger wrapper for onGameLogCreated.
 * Only applies when bracketId + bracketMatchId are present on the created log.
 */
export async function applyBracketOutcomeFromGameLogCreate(
  gameLogId: string,
  gameLogData: Record<string, unknown>
): Promise<void> {
  const bracketId =
    typeof gameLogData.bracketId === "string" ?
      gameLogData.bracketId.trim() :
      "";
  const bracketMatchId =
    typeof gameLogData.bracketMatchId === "string" ?
      gameLogData.bracketMatchId.trim() :
      "";

  if (!bracketId || !bracketMatchId) {
    return;
  }

  const communityId =
    typeof gameLogData.communityId === "string" ? gameLogData.communityId : "";

  const participantProfileIds = Array.isArray(
    gameLogData.participantProfileIds
  ) ? (gameLogData.participantProfileIds as string[]) : [];
  const winnerProfileIds = Array.isArray(gameLogData.winnerProfileIds) ?
    (gameLogData.winnerProfileIds as string[]) :
    [];
  const loserProfileIds = Array.isArray(gameLogData.loserProfileIds) ?
    (gameLogData.loserProfileIds as string[]) :
    [];

  if (!communityId || participantProfileIds.length === 0 ||
      winnerProfileIds.length === 0 || loserProfileIds.length === 0) {
    logger.warn("applyBracketOutcomeFromGameLogCreate: missing fields", {
      gameLogId,
      bracketId,
      bracketMatchId,
      communityIdPresent: !!communityId,
      participantCount: participantProfileIds.length,
      winnerCount: winnerProfileIds.length,
      loserCount: loserProfileIds.length,
    });
    return;
  }

  const bracketRef = db.collection("brackets").doc(bracketId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(bracketRef);
    if (!snap.exists) {
      logger.warn("applyBracketOutcomeFromGameLogCreate: bracket missing", {
        gameLogId,
        bracketId,
      });
      return;
    }

    const bracket = snap.data() as unknown as BracketDocument;
    const {updatedBracket, result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId,
        communityId,
        participantProfileIds,
        winnerProfileIds,
        loserProfileIds,
      }
    );

    if (!result.didUpdate) {
      logger.info("applyBracketOutcomeFromGameLogCreate: no update (idempotent/invalid)", {
        gameLogId,
        bracketId,
        bracketMatchId,
      });
      return;
    }

    tx.update(bracketRef, {
      rounds: updatedBracket.rounds,
      status: updatedBracket.status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });
}

/**
 * Optional callable backfill/repair.
 * Non-primary: bracket progression is normally driven by game log creation.
 */
export const updateMatchResult = onCall(
  {region},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;

    const bracketId =
      typeof request.data?.bracketId === "string" ?
        request.data.bracketId.trim() :
        "";
    const matchId =
      typeof request.data?.matchId === "string" ?
        request.data.matchId.trim() :
        "";

    const winnerProfileIds = Array.isArray(request.data?.winnerProfileIds) ?
      (request.data.winnerProfileIds as string[]) :
      [];
    const loserProfileIds = Array.isArray(request.data?.loserProfileIds) ?
      (request.data.loserProfileIds as string[]) :
      [];

    if (!bracketId || !matchId) {
      throw new HttpsError("invalid-argument", "bracketId and matchId are required");
    }
    if (winnerProfileIds.length < 1 || loserProfileIds.length < 1) {
      throw new HttpsError("invalid-argument", "winnerProfileIds and loserProfileIds must be non-empty");
    }
    if (!winnerProfileIds.every((v) => typeof v === "string") ||
        !loserProfileIds.every((v) => typeof v === "string")) {
      throw new HttpsError("invalid-argument", "winnerProfileIds and loserProfileIds must be string arrays");
    }

    const bracketRef = db.collection("brackets").doc(bracketId);
    const bracketSnap = await bracketRef.get();
    if (!bracketSnap.exists) {
      throw new HttpsError("not-found", "Bracket not found");
    }
    const bracket = bracketSnap.data() as unknown as BracketDocument;

    // Require membership.
    const membershipId = `${bracket.communityId}_${uid}`;
    const membershipSnap = await db.collection("memberships").doc(membershipId).get();
    if (!membershipSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a member of this bracket community");
    }

    // Use match participantProfileIds as derived participant set.
    const target = findMatch(bracket, matchId);
    if (!target) {
      throw new HttpsError("not-found", "Match not found in bracket");
    }
    const participantProfileIds = target.match.participantProfileIds;

    // Apply via pure function to guarantee same validation.
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(bracketRef);
      if (!snap.exists) return;
      const freshBracket = snap.data() as unknown as BracketDocument;

      const target2 = findMatch(freshBracket, matchId);
      const participantProfileIdsFresh = target2?.match.participantProfileIds ?? participantProfileIds;

      const {updatedBracket, result} = applyGameLogOutcomeToBracketDoc(
        freshBracket,
        {
          bracketMatchId: matchId,
          communityId: bracket.communityId,
          participantProfileIds: participantProfileIdsFresh,
          winnerProfileIds,
          loserProfileIds,
        }
      );

      if (!result.didUpdate) return;

      tx.update(bracketRef, {
        rounds: updatedBracket.rounds,
        status: updatedBracket.status,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return newEnvelope({});
  }
);

