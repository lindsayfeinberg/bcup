import {
  CUSTOM_GAME_TYPE_SENTINEL,
  KNOWN_GAME_TYPES,
  oddsBucketKeyFromData,
} from "./oddsRecalc.js";

describe("oddsBucketKeyFromData (Phase E2)", () => {
  it("buckets built-in types (case-insensitive)", () => {
    expect(oddsBucketKeyFromData({gameType: "pong"})).toBe("PONG");
    expect(oddsBucketKeyFromData({gameType: "PONG"})).toBe("PONG");
  });

  it("uses CUSTOM:definitionId when customGameDefinitionId is set", () => {
    expect(
      oddsBucketKeyFromData({
        gameType: CUSTOM_GAME_TYPE_SENTINEL,
        customGameDefinitionId: "gd_abc",
      })
    ).toBe("CUSTOM:gd_abc");
  });

  it("prefers built-in gameType when it matches known list", () => {
    expect(
      oddsBucketKeyFromData({
        gameType: "PONG",
        customGameDefinitionId: "should_not_apply",
      })
    ).toBe("PONG");
  });

  it("uses OTHER: prefix for unknown gameType without custom id", () => {
    expect(oddsBucketKeyFromData({gameType: "RUSKI"})).toBe("OTHER:RUSKI");
  });

  it("returns null for CUSTOM sentinel without definition id", () => {
    expect(
      oddsBucketKeyFromData({gameType: CUSTOM_GAME_TYPE_SENTINEL})
    ).toBeNull();
  });

  it("exports known game types list", () => {
    expect(KNOWN_GAME_TYPES).toContain("CROSSFIRE");
  });
});
