import {Timestamp} from "firebase-admin/firestore";

// MARK: - Enums

export type BracketStatus = "DRAFT" | "ACTIVE" | "COMPLETE";
export type SeedMethod = "COMMUNITY_ODDS" | "MANUAL" | "RANDOM";

export const BRACKET_STATUSES: BracketStatus[] = [
  "DRAFT",
  "ACTIVE",
  "COMPLETE",
];

export const SEED_METHODS: SeedMethod[] = [
  "COMMUNITY_ODDS",
  "MANUAL",
  "RANDOM",
];

// MARK: - Match shape
//
// Unplayed matches omit winnerProfileIds and loserProfileIds entirely
// (i.e. the keys are absent, not present as []). This allows a clean
// "has this match been played?" check via `"winnerProfileIds" in match`.
// T10.2+ must not write empty arrays for unplayed matches.

export interface BracketMatch {
  matchId: string;
  roundNumber: number;
  participantProfileIds: string[];
  winnerProfileIds?: string[];
  loserProfileIds?: string[];
  /** Round 2+ placeholders: use with empty `participantProfileIds` (T10.7). */
  feederMatchIds?: string[];
}

// MARK: - Round shape
//
// rounds is Array<BracketRound> where each round groups its matches.
// roundNumber starts at 1. This structure keeps T10.7 rendering
// (group by round) and updateMatchResult lookups (find by matchId
// across rounds) both straightforward.

export interface BracketRound {
  roundNumber: number;
  matches: BracketMatch[];
}

// MARK: - Top-level document

export interface BracketDocument {
  id: string;
  communityId: string;
  participantProfileIds: string[];
  seedMethod: SeedMethod;
  teamSize: number;
  status: BracketStatus;
  rounds: BracketRound[];
  createdAt: Timestamp | unknown;
  updatedAt: Timestamp | unknown;
}

// MARK: - Enum validators

/**
 * Returns true if value is a valid SeedMethod.
 * @param {unknown} value Value to check.
 * @return {boolean}
 */
export function isValidSeedMethod(value: unknown): value is SeedMethod {
  return (
    typeof value === "string" &&
    (SEED_METHODS as string[]).includes(value)
  );
}

/**
 * Returns true if value is a valid BracketStatus.
 * @param {unknown} value Value to check.
 * @return {boolean}
 */
export function isValidBracketStatus(
  value: unknown
): value is BracketStatus {
  return (
    typeof value === "string" &&
    (BRACKET_STATUSES as string[]).includes(value)
  );
}

// MARK: - Match validation

export type MatchValidationError =
  | "MISSING_MATCH_ID"
  | "PARTICIPANTS_TOO_FEW"
  | "PARTICIPANTS_HAS_DUPLICATES"
  | "FEEDER_MATCH_IDS_INVALID"
  | "PLACEHOLDER_PARTICIPANTS_NOT_EMPTY"
  | "PLACEHOLDER_MUST_NOT_HAVE_OUTCOME"
  // NOTE: Bye matches may be finalized with only one side (winner or loser).
  | "WINNERS_EMPTY"
  | "LOSERS_EMPTY"
  | "WINNER_NOT_SUBSET"
  | "LOSER_NOT_SUBSET"
  | "WINNERS_DO_NOT_COVER_PARTICIPANTS"
  | "LOSERS_DO_NOT_COVER_PARTICIPANTS"
  | "WINNER_LOSER_OVERLAP"
  | "WINNERS_HAS_DUPLICATES"
  | "LOSERS_HAS_DUPLICATES";

export interface MatchValidationResult {
  valid: boolean;
  errors: MatchValidationError[];
}

/**
 * Validates a single bracket match object.
 * Unplayed matches (no winnerProfileIds / loserProfileIds keys) are valid.
 * When either outcome key is present, both must be present with non-empty
 * arrays; then subset + disjoint checks apply.
 * Minimum participants is 2 for scheduled matches (1v1 / 2v2+).
 * Placeholder matches use `feederMatchIds` (length 2) and
 * `participantProfileIds: []`.
 * @param {unknown} m Raw match data.
 * @return {MatchValidationResult} Validation result with error list.
 */
export function validateBracketMatch(
  m: unknown
): MatchValidationResult {
  const errors: MatchValidationError[] = [];

  if (
    typeof m !== "object" ||
    m === null ||
    Array.isArray(m)
  ) {
    return {valid: false, errors: ["MISSING_MATCH_ID"]};
  }

  const match = m as Record<string, unknown>;

  // matchId
  if (
    typeof match.matchId !== "string" ||
    match.matchId.trim() === ""
  ) {
    errors.push("MISSING_MATCH_ID");
  }

  const hasFeederKey = "feederMatchIds" in match;
  const feederRaw = match.feederMatchIds;

  if (hasFeederKey) {
    let feederOk = false;
    if (
      Array.isArray(feederRaw) &&
      feederRaw.length === 2 &&
      feederRaw.every(
        (id) => typeof id === "string" && id.trim() !== ""
      )
    ) {
      feederOk = true;
    }
    if (!feederOk) {
      errors.push("FEEDER_MATCH_IDS_INVALID");
    }

    const participants = match.participantProfileIds;
    // Placeholder participants may be partially prefilled (e.g. bye-side winners),
    // but outcomes must not exist yet.
    if (!Array.isArray(participants)) {
      errors.push("PLACEHOLDER_PARTICIPANTS_NOT_EMPTY");
    }

    if ("winnerProfileIds" in match || "loserProfileIds" in match) {
      errors.push("PLACEHOLDER_MUST_NOT_HAVE_OUTCOME");
    }

    return {valid: errors.length === 0, errors};
  }

  // participantProfileIds — scheduled match
  const participants = match.participantProfileIds;
  if (!Array.isArray(participants) || participants.length < 1) {
    errors.push("PARTICIPANTS_TOO_FEW");
    return {valid: false, errors};
  }
  const participantSet = new Set(participants as string[]);
  if (participantSet.size !== participants.length) {
    errors.push("PARTICIPANTS_HAS_DUPLICATES");
  }

  const hasWinners = "winnerProfileIds" in match;
  const hasLosers = "loserProfileIds" in match;

  if (!hasWinners && !hasLosers) {
    if (participantSet.size < 2) {
      errors.push("PARTICIPANTS_TOO_FEW");
    }
    return {valid: errors.length === 0, errors};
  }

  // winnerProfileIds
  const winners = match.winnerProfileIds as string[] | undefined;
  if (hasWinners) {
    if (!Array.isArray(winners) || winners.length === 0) {
      errors.push("WINNERS_EMPTY");
    } else {
      if (new Set(winners).size !== winners.length) {
        errors.push("WINNERS_HAS_DUPLICATES");
      }
      const notSubset = winners.some(
        (id) => !participantSet.has(id)
      );
      if (notSubset) errors.push("WINNER_NOT_SUBSET");
    }
  }

  // loserProfileIds
  const losers = match.loserProfileIds as string[] | undefined;
  if (hasLosers) {
    if (!Array.isArray(losers) || losers.length === 0) {
      errors.push("LOSERS_EMPTY");
    } else {
      if (new Set(losers).size !== losers.length) {
        errors.push("LOSERS_HAS_DUPLICATES");
      }
      const notSubset = losers.some(
        (id) => !participantSet.has(id)
      );
      if (notSubset) errors.push("LOSER_NOT_SUBSET");
    }
  }

  // If only one side has outcome keys (e.g. bye match), ensure it covers all participants.
  // This keeps bye match semantics consistent: winners/losers are the advancing side.
  if (hasWinners && !hasLosers) {
    const winnerSet = new Set((match.winnerProfileIds as string[]) ?? []);
    const allCovered = [...participantSet].every((id) => winnerSet.has(id));
    if (!allCovered) {
      errors.push("WINNERS_DO_NOT_COVER_PARTICIPANTS");
    }
    if (participantSet.size < 2) {
      // allow bye matches with a single "team" worth of participants
    }
  } else if (!hasWinners && hasLosers) {
    const loserSet = new Set((match.loserProfileIds as string[]) ?? []);
    const allCovered = [...participantSet].every((id) => loserSet.has(id));
    if (!allCovered) {
      errors.push("LOSERS_DO_NOT_COVER_PARTICIPANTS");
    }
  } else if (hasWinners && hasLosers) {
    // When both sides exist, scheduled matches must have at least 2 participants total.
    if (participantSet.size < 2) {
      errors.push("PARTICIPANTS_TOO_FEW");
    }
  }

  // winner/loser overlap
  if (
    Array.isArray(winners) &&
    winners.length > 0 &&
    Array.isArray(losers) &&
    losers.length > 0
  ) {
    const winnerSet = new Set(winners);
    const overlap = losers.some((id) => winnerSet.has(id));
    if (overlap) errors.push("WINNER_LOSER_OVERLAP");
  }

  return {valid: errors.length === 0, errors};
}

// MARK: - Rounds validation

export interface RoundsValidationResult {
  valid: boolean;
  errors: string[];
}

/**
 * Validates the full rounds array of a bracket document.
 * Checks: array type, each round has roundNumber and matches array,
 * roundNumbers are unique and start at 1, each match passes
 * validateBracketMatch, matchIds are unique across all rounds.
 * @param {unknown} rounds Raw rounds data.
 * @return {RoundsValidationResult} Validation result with error list.
 */
export function validateRoundsStructure(
  rounds: unknown
): RoundsValidationResult {
  const errors: string[] = [];

  if (!Array.isArray(rounds)) {
    return {valid: false, errors: ["rounds must be an array"]};
  }

  const roundNumbers = new Set<number>();
  const allMatchIds = new Set<string>();

  for (let ri = 0; ri < rounds.length; ri++) {
    const round = rounds[ri] as Record<string, unknown>;

    if (typeof round !== "object" || round === null) {
      errors.push(`rounds[${ri}]: not an object`);
      continue;
    }

    const rn = round.roundNumber;
    if (typeof rn !== "number" || !Number.isInteger(rn) || rn < 1) {
      errors.push(
        `rounds[${ri}]: roundNumber must be integer >= 1`
      );
    } else if (roundNumbers.has(rn)) {
      errors.push(`rounds[${ri}]: duplicate roundNumber ${rn}`);
    } else {
      roundNumbers.add(rn);
    }

    if (!Array.isArray(round.matches)) {
      errors.push(`rounds[${ri}]: matches must be an array`);
      continue;
    }

    const matches = round.matches as unknown[];
    for (let mi = 0; mi < matches.length; mi++) {
      const result = validateBracketMatch(matches[mi]);
      if (!result.valid) {
        errors.push(
          `rounds[${ri}].matches[${mi}]: ${result.errors.join(", ")}`
        );
      }
      const matchObj = matches[mi] as Record<string, unknown>;
      const matchId =
        typeof matchObj.matchId === "string" ?
          matchObj.matchId :
          null;
      if (matchId) {
        if (allMatchIds.has(matchId)) {
          errors.push(
            `rounds[${ri}].matches[${mi}]: ` +
            `duplicate matchId ${matchId}`
          );
        } else {
          allMatchIds.add(matchId);
        }
      }
    }
  }

  return {valid: errors.length === 0, errors};
}

/**
 * Ensures every profile in the bracket snapshot appears in some round-1 match
 * (and round-1 has no extras). Catches generation bugs that would strand members.
 * Skip for empty rounds (e.g. MANUAL draft before finalize).
 * @param {BracketRound[]} rounds Typed rounds.
 * @param {string[]} participantProfileIds Bracket-level roster from memberships.
 * @return {RoundsValidationResult} Whether sets match.
 */
export function validateRoundOneCoversParticipants(
  rounds: BracketRound[],
  participantProfileIds: string[]
): RoundsValidationResult {
  const errors: string[] = [];
  if (rounds.length === 0) {
    return {valid: true, errors: []};
  }
  const r1 = rounds.find((r) => r.roundNumber === 1);
  if (!r1) {
    errors.push("round 1 missing");
    return {valid: false, errors};
  }
  const inMatches = new Set<string>();
  for (const m of r1.matches) {
    const parts = m.participantProfileIds ?? [];
    for (const id of parts) {
      if (typeof id === "string" && id.length > 0) {
        inMatches.add(id);
      }
    }
  }
  const expected = new Set(participantProfileIds);
  for (const id of expected) {
    if (!inMatches.has(id)) {
      errors.push(`round1 missing participant ${id}`);
    }
  }
  for (const id of inMatches) {
    if (!expected.has(id)) {
      errors.push(`round1 unexpected participant ${id}`);
    }
  }
  return {valid: errors.length === 0, errors};
}
