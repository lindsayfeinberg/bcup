import {resolveEffectiveOdds} from "./effectiveOdds.js";

describe("resolveEffectiveOdds", () => {
  it("returns overallOdds when communityGamesPlayed is 0 (sparse)", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0.75,
      communityOdds: 0,
      communityGamesPlayed: 0,
    });
    expect(result.effectiveOdds).toBe(0.75);
    expect(result.usedCommunityOdds).toBe(false);
  });

  it("returns communityOdds when communityGamesPlayed >= 1", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0.75,
      communityOdds: 0.5,
      communityGamesPlayed: 1,
    });
    expect(result.effectiveOdds).toBe(0.5);
    expect(result.usedCommunityOdds).toBe(true);
  });

  it("returns communityOdds when overall and community differ", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0.9,
      communityOdds: 0.3,
      communityGamesPlayed: 5,
    });
    expect(result.effectiveOdds).toBe(0.3);
    expect(result.usedCommunityOdds).toBe(true);
  });

  it("treats missing communityGamesPlayed as sparse", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0.6,
      communityOdds: 0,
      communityGamesPlayed: undefined as unknown as number,
    });
    expect(result.effectiveOdds).toBe(0.6);
    expect(result.usedCommunityOdds).toBe(false);
  });

  it("returns 0 when both are 0 and sparse", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0,
      communityOdds: 0,
      communityGamesPlayed: 0,
    });
    expect(result.effectiveOdds).toBe(0);
    expect(result.usedCommunityOdds).toBe(false);
  });

  it("communityOdds of 0 with games > 0 is not sparse", () => {
    const result = resolveEffectiveOdds({
      overallOdds: 0.5,
      communityOdds: 0,
      communityGamesPlayed: 3,
    });
    expect(result.effectiveOdds).toBe(0);
    expect(result.usedCommunityOdds).toBe(true);
  });
});
