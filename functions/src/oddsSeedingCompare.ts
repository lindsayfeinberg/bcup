import {
  resolveEffectiveOdds,
  EffectiveOddsInput,
} from "./effectiveOdds.js";

/**
   * Input type for one participant in odds-based seeding.
   * createdAt is stored as milliseconds since epoch (number).
   * Use Timestamp.toMillis() before passing in from Firestore.
   */
export interface SeedingParticipant {
    profileId: string;
    createdAtMs: number;
    overallOdds: number;
    overallGamesPlayed: number;
    communityOdds: number;
    communityGamesPlayed: number;
  }

/**
   * Optional head-to-head lookup.
   * h2h.get(aId)?.get(bId) = number of times A beat B in
   * eligible logs where both were participants.
   */
export type H2HMap = Map<string, Map<string, number>>;

/**
   * Compares two participants for COMMUNITY_ODDS bracket seeding.
   * Returns negative if a sorts before b (a is better seed).
   * Tie-break order per api-contracts:
   * 1. Higher effective odds (DESC)
   * 2. More games in same scope as odds (DESC)
   * 3. Head-to-head wins (DESC) if data provided
   * 4. Earlier createdAt (ASC)
   * 5. Lexicographic profileId (ASC)
   * @param {SeedingParticipant} a First participant.
   * @param {SeedingParticipant} b Second participant.
   * @param {H2HMap} h2h Optional head-to-head lookup.
   * @return {number} Sort comparator value.
   */
export function compareParticipantsForOddsSeeding(
  a: SeedingParticipant,
  b: SeedingParticipant,
  h2h?: H2HMap
): number {
  const inputA: EffectiveOddsInput = {
    overallOdds: a.overallOdds,
    communityOdds: a.communityOdds,
    communityGamesPlayed: a.communityGamesPlayed,
  };
  const inputB: EffectiveOddsInput = {
    overallOdds: b.overallOdds,
    communityOdds: b.communityOdds,
    communityGamesPlayed: b.communityGamesPlayed,
  };

  const resolvedA = resolveEffectiveOdds(inputA);
  const resolvedB = resolveEffectiveOdds(inputB);

  // Step 1: effective odds DESC
  if (resolvedA.effectiveOdds !== resolvedB.effectiveOdds) {
    return resolvedB.effectiveOdds - resolvedA.effectiveOdds;
  }

  // Step 2: games in same scope DESC
  const gamesA = resolvedA.usedCommunityOdds ?
    a.communityGamesPlayed :
    a.overallGamesPlayed;
  const gamesB = resolvedB.usedCommunityOdds ?
    b.communityGamesPlayed :
    b.overallGamesPlayed;
  if (gamesA !== gamesB) {
    return gamesB - gamesA;
  }

  // Step 3: head-to-head wins DESC (skip if no data)
  if (h2h) {
    const aBeatsB = h2h.get(a.profileId)?.get(b.profileId) ?? 0;
    const bBeatsA = h2h.get(b.profileId)?.get(a.profileId) ?? 0;
    if (aBeatsB !== bBeatsA) {
      return bBeatsA - aBeatsB;
    }
  }

  // Step 4: earlier createdAt ASC
  if (a.createdAtMs !== b.createdAtMs) {
    return a.createdAtMs - b.createdAtMs;
  }

  // Step 5: lexicographic profileId ASC
  if (a.profileId === b.profileId) return 0;
  return a.profileId < b.profileId ? -1 : 1;
}

/**
   * Sorts participants for COMMUNITY_ODDS bracket seeding.
   * Best seed first (highest effective odds).
   * @param {SeedingParticipant[]} participants List to sort.
   * @param {H2HMap} h2h Optional head-to-head lookup.
   * @return {SeedingParticipant[]} New sorted array.
   */
export function sortParticipantsForOddsSeeding(
  participants: SeedingParticipant[],
  h2h?: H2HMap
): SeedingParticipant[] {
  return [...participants].sort((a, b) =>
    compareParticipantsForOddsSeeding(a, b, h2h)
  );
}
