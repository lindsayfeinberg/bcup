/**
 * T09.4: Sparse-data fallback for odds-based seeding.
 *
 * "Sparse" means the profile has zero eligible in-community games.
 * When sparse, use overallOdds as the effective odds value.
 * When not sparse, use communityOdds.
 *
 * Missing fields are treated as sparse (use overall) per
 * data-contract defaults (communityGamesPlayed defaults to 0).
 */

export interface EffectiveOddsInput {
    overallOdds: number;
    communityOdds: number;
    communityGamesPlayed: number;
  }

export interface EffectiveOddsResult {
    effectiveOdds: number;
    usedCommunityOdds: boolean;
  }

/**
   * Returns the effective odds for bracket seeding.
   * Uses communityOdds when communityGamesPlayed > 0,
   * otherwise falls back to overallOdds (sparse).
   * @param {EffectiveOddsInput} input Odds and game count fields.
   * @return {EffectiveOddsResult} Effective odds and which source
   * was used.
   */
export function resolveEffectiveOdds(
  input: EffectiveOddsInput
): EffectiveOddsResult {
  const games = input.communityGamesPlayed ?? 0;
  if (games === 0) {
    return {
      effectiveOdds: input.overallOdds ?? 0,
      usedCommunityOdds: false,
    };
  }
  return {
    effectiveOdds: input.communityOdds ?? 0,
    usedCommunityOdds: true,
  };
}
