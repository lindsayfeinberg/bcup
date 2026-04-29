import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import type {
  BracketDocument,
  BracketMatch,
} from "./bracketModel.js";

// Match validation lives in bracketModel.ts, but we keep some additional
// invariants local to this file (e.g. "winners+losers partition match").
import {validateBracketMatch, validateRoundsStructure} from "./bracketModel.js";
import {makeMatchId} from "./bracketSeeding.js";

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
        feederA && hasOutcomeKeys(feederA.match) ?
          feederA.match.winnerProfileIds ?? [] :
          [];
      const feederBWinner =
        feederB && hasOutcomeKeys(feederB.match) ?
          feederB.match.winnerProfileIds ?? [] :
          [];

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
 * Strips all match outcomes and forces ACTIVE so replay can re-apply logs.
 * @param {BracketDocument} bracket Bracket snapshot.
 * @return {BracketDocument} Deep-cloned bracket with outcomes removed.
 */
function stripAllMatchOutcomes(bracket: BracketDocument): BracketDocument {
  const b = deepCloneBracketDoc(bracket);
  for (const round of b.rounds) {
    for (const match of round.matches) {
      delete (match as BracketMatch & {winnerProfileIds?: string[]}).winnerProfileIds;
      delete (match as BracketMatch & {loserProfileIds?: string[]}).loserProfileIds;
    }
  }
  if (b.status === "COMPLETE") {
    b.status = "ACTIVE";
  }
  return b;
}

/**
 * Re-finalizes structural round-1 bye matches after outcome strip.
 * Bye rows have fewer than `teamSize * 2` participants and no losers;
 * restoring `winnerProfileIds` keeps validators and feeder advance
 * consistent before placeholder geometry restore.
 * @param {BracketDocument} bracket Bracket after `stripAllMatchOutcomes`.
 */
function restoreStructuralRound1ByeOutcomes(bracket: BracketDocument): void {
  const cap = bracket.teamSize * 2;
  for (const round of bracket.rounds) {
    if (round.roundNumber !== 1) continue;
    for (const match of round.matches) {
      if (isPlaceholderMatch(match)) continue;
      if (hasOutcomeKeys(match)) continue;
      const p = match.participantProfileIds ?? [];
      if (p.length === 0 || p.length >= cap) continue;
      (match as BracketMatch).winnerProfileIds = [...p];
    }
  }
}

/**
 * Clears placeholder participant staging and restores `feederMatchIds` for
 * promoted placeholders when both inferred feeder matches exist (standard tree).
 * @param {BracketDocument} bracket Bracket after outcome strip.
 * @param {string} bracketId Bracket doc id (used in matchId geometry).
 */
function restorePlaceholderFeedersFromGeometry(
  bracket: BracketDocument,
  bracketId: string
): void {
  for (const round of bracket.rounds) {
    const r = round.roundNumber;
    if (r < 2) continue;

    round.matches.forEach((match, mIdx) => {
      if (isPlaceholderMatch(match)) {
        match.participantProfileIds = [];
        return;
      }
      if (hasOutcomeKeys(match)) {
        return;
      }

      const inferredF1 = makeMatchId(bracketId, r - 1, mIdx * 2);
      const inferredF2 = makeMatchId(bracketId, r - 1, mIdx * 2 + 1);
      const f1node = findMatch(bracket, inferredF1);
      const f2node = findMatch(bracket, inferredF2);
      if (f1node && f2node) {
        (match as BracketMatch).feederMatchIds = [inferredF1, inferredF2];
        const prefill: string[] = [];
        const seen = new Set<string>();
        for (const node of [f1node, f2node]) {
          const w = node.match.winnerProfileIds;
          if (!Array.isArray(w) || w.length === 0) continue;
          for (const id of w) {
            if (!seen.has(id)) {
              seen.add(id);
              prefill.push(id);
            }
          }
        }
        match.participantProfileIds = prefill;
      }
    });
  }
}

/**
 * Reads Firestore `createdAt` for stable log ordering.
 * @param {Record<string, unknown>} data Game log fields.
 * @return {number} Epoch millis, or 0 if missing.
 */
function createdAtMillis(data: Record<string, unknown>): number {
  const t = data.createdAt;
  if (t && typeof (t as {toMillis?: () => number}).toMillis === "function") {
    return (t as {toMillis: () => number}).toMillis();
  }
  return 0;
}

/**
 * Rebuilds bracket rounds/status by replaying remaining game logs in
 * `createdAt` order (B1).
 *
 * @param {BracketDocument} bracket Current Firestore bracket snapshot.
 * @param {Record<string, unknown>[]} gameLogRows Remaining logs for this
 *   bracket, including `createdAt` and outcome fields.
 * @param {string} bracketId Expected bracket id string.
 * @return {BracketDocument} Recomputed bracket document.
 */
export function rebuildBracketFromRemainingGameLogs(
  bracket: BracketDocument,
  gameLogRows: Record<string, unknown>[],
  bracketId: string
): BracketDocument {
  let working = stripAllMatchOutcomes(bracket);
  restoreStructuralRound1ByeOutcomes(working);
  restorePlaceholderFeedersFromGeometry(working, bracketId);
  working.status = "ACTIVE";

  const sorted = [...gameLogRows].sort((a, b) => {
    const ma = createdAtMillis(a);
    const mb = createdAtMillis(b);
    if (ma !== mb) return ma - mb;
    const ida = typeof a.__gameLogId === "string" ? a.__gameLogId : "";
    const idb = typeof b.__gameLogId === "string" ? b.__gameLogId : "";
    return ida.localeCompare(idb);
  });

  for (const data of sorted) {
    const bid =
      typeof data.bracketId === "string" ? data.bracketId.trim() : "";
    const mid =
      typeof data.bracketMatchId === "string" ?
        data.bracketMatchId.trim() :
        "";
    if (bid !== bracketId || !mid) continue;

    const participantProfileIds =
      Array.isArray(data.participantProfileIds) ?
        (data.participantProfileIds as string[]) :
        [];
    const winnerProfileIds =
      Array.isArray(data.winnerProfileIds) ?
        (data.winnerProfileIds as string[]) :
        [];
    const loserProfileIds =
      Array.isArray(data.loserProfileIds) ?
        (data.loserProfileIds as string[]) :
        [];
    if (
      participantProfileIds.length === 0 ||
      winnerProfileIds.length === 0 ||
      loserProfileIds.length === 0
    ) {
      continue;
    }

    const communityId =
      typeof data.communityId === "string" && data.communityId ?
        data.communityId :
        working.communityId;

    const {updatedBracket} = applyGameLogOutcomeToBracketDoc(working, {
      bracketMatchId: mid,
      communityId,
      participantProfileIds,
      winnerProfileIds,
      loserProfileIds,
    });
    working = updatedBracket;
  }

  return working;
}

/**
 * After a bracket-linked game log is deleted, re-sync the bracket from all
 * remaining `gameLogs` with the same `bracketId` (replay in `createdAt` order).
 *
 * @param {string} deletedGameLogId Deleted document id (for logs).
 * @param {Record<string, unknown>} gameLogData Snapshot of deleted log data.
 * @return {Promise<void>} Resolves when the transaction completes.
 */
export async function applyBracketUndoFromGameLogDelete(
  deletedGameLogId: string,
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
  if (!communityId) {
    logger.warn("applyBracketUndoFromGameLogDelete: missing communityId", {
      deletedGameLogId,
      bracketId,
    });
    return;
  }

  const bracketRef = db.collection("brackets").doc(bracketId);

  await db.runTransaction(async (tx) => {
    const bSnap = await tx.get(bracketRef);
    if (!bSnap.exists) {
      logger.warn("applyBracketUndoFromGameLogDelete: bracket missing", {
        deletedGameLogId,
        bracketId,
      });
      return;
    }

    const bracket = bSnap.data() as unknown as BracketDocument;
    if (bracket.communityId !== communityId) {
      logger.warn("applyBracketUndoFromGameLogDelete: community mismatch", {
        deletedGameLogId,
        bracketId,
      });
      return;
    }
    if (bracket.status === "DRAFT") {
      return;
    }

    const logsSnap = await tx.get(
      db.collection("gameLogs").where("bracketId", "==", bracketId)
    );

    const rows: Record<string, unknown>[] = logsSnap.docs.map((d) => {
      const data = d.data() as Record<string, unknown>;
      return {...data, __gameLogId: d.id};
    });

    const rebuilt = rebuildBracketFromRemainingGameLogs(
      bracket,
      rows,
      bracketId
    );

    const validation = validateRoundsStructure(rebuilt.rounds);
    if (!validation.valid) {
      logger.error(
        "applyBracketUndoFromGameLogDelete: rebuilt rounds invalid",
        {
          deletedGameLogId,
          bracketId,
          errors: validation.errors,
        }
      );
      return;
    }

    tx.update(bracketRef, {
      rounds: rebuilt.rounds,
      status: rebuilt.status,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    logger.info("applyBracketUndoFromGameLogDelete: bracket rebuilt", {
      deletedGameLogId,
      bracketId,
      bracketMatchId,
      remainingLogs: rows.length,
      status: rebuilt.status,
    });
  });
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

