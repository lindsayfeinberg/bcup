import {
  isValidSeedMethod,
  isValidBracketStatus,
  validateBracketMatch,
  validateRoundsStructure,
} from "./bracketModel.js";

describe("isValidSeedMethod", () => {
  it("accepts valid seed methods", () => {
    expect(isValidSeedMethod("COMMUNITY_ODDS")).toBe(true);
    expect(isValidSeedMethod("MANUAL")).toBe(true);
    expect(isValidSeedMethod("RANDOM")).toBe(true);
  });
  it("rejects invalid values", () => {
    expect(isValidSeedMethod("INVALID")).toBe(false);
    expect(isValidSeedMethod(null)).toBe(false);
    expect(isValidSeedMethod(1)).toBe(false);
  });
});

describe("isValidBracketStatus", () => {
  it("accepts valid statuses", () => {
    expect(isValidBracketStatus("DRAFT")).toBe(true);
    expect(isValidBracketStatus("ACTIVE")).toBe(true);
    expect(isValidBracketStatus("COMPLETE")).toBe(true);
  });
  it("rejects invalid values", () => {
    expect(isValidBracketStatus("draft")).toBe(false);
    expect(isValidBracketStatus(undefined)).toBe(false);
  });
});

describe("validateBracketMatch", () => {
  const validUnplayed = {
    matchId: "match_1",
    roundNumber: 1,
    participantProfileIds: ["uid_a", "uid_b"],
  };

  const validPlayed = {
    matchId: "match_1",
    roundNumber: 1,
    participantProfileIds: ["uid_a", "uid_b"],
    winnerProfileIds: ["uid_a"],
    loserProfileIds: ["uid_b"],
  };

  it("accepts valid unplayed match", () => {
    const r = validateBracketMatch(validUnplayed);
    expect(r.valid).toBe(true);
    expect(r.errors).toHaveLength(0);
  });

  it("accepts valid played match", () => {
    const r = validateBracketMatch(validPlayed);
    expect(r.valid).toBe(true);
    expect(r.errors).toHaveLength(0);
  });

  it("accepts valid 2v2 match", () => {
    const r = validateBracketMatch({
      matchId: "match_2v2",
      roundNumber: 1,
      participantProfileIds: ["a", "b", "c", "d"],
      winnerProfileIds: ["a", "b"],
      loserProfileIds: ["c", "d"],
    });
    expect(r.valid).toBe(true);
  });

  it("rejects missing matchId", () => {
    const r = validateBracketMatch({
      ...validUnplayed,
      matchId: "",
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("MISSING_MATCH_ID");
  });

  it("rejects fewer than 2 participants", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("PARTICIPANTS_TOO_FEW");
  });

  it("rejects duplicate participants", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_a"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("PARTICIPANTS_HAS_DUPLICATES");
  });

  it("rejects winner not subset of participants", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b"],
      winnerProfileIds: ["uid_c"],
      loserProfileIds: ["uid_b"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("WINNER_NOT_SUBSET");
  });

  it("rejects loser not subset of participants", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b"],
      winnerProfileIds: ["uid_a"],
      loserProfileIds: ["uid_z"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("LOSER_NOT_SUBSET");
  });

  it("rejects winner/loser overlap", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b"],
      winnerProfileIds: ["uid_a"],
      loserProfileIds: ["uid_a"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("WINNER_LOSER_OVERLAP");
  });

  it("rejects duplicate winners", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b"],
      winnerProfileIds: ["uid_a", "uid_a"],
      loserProfileIds: ["uid_b"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("WINNERS_HAS_DUPLICATES");
  });

  it("rejects duplicate losers", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b", "uid_c"],
      winnerProfileIds: ["uid_a"],
      loserProfileIds: ["uid_b", "uid_b"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("LOSERS_HAS_DUPLICATES");
  });

  it("rejects empty winners array when key present", () => {
    const r = validateBracketMatch({
      matchId: "match_1",
      roundNumber: 1,
      participantProfileIds: ["uid_a", "uid_b"],
      winnerProfileIds: [],
      loserProfileIds: ["uid_b"],
    });
    expect(r.valid).toBe(false);
    expect(r.errors).toContain("WINNERS_EMPTY");
  });
});

describe("validateRoundsStructure", () => {
  it("accepts empty rounds array", () => {
    const r = validateRoundsStructure([]);
    expect(r.valid).toBe(true);
  });

  it("accepts valid single round", () => {
    const r = validateRoundsStructure([
      {
        roundNumber: 1,
        matches: [
          {
            matchId: "m1",
            roundNumber: 1,
            participantProfileIds: ["a", "b"],
          },
        ],
      },
    ]);
    expect(r.valid).toBe(true);
  });

  it("accepts valid multi-round structure", () => {
    const r = validateRoundsStructure([
      {
        roundNumber: 1,
        matches: [
          {
            matchId: "m1",
            roundNumber: 1,
            participantProfileIds: ["a", "b"],
            winnerProfileIds: ["a"],
            loserProfileIds: ["b"],
          },
        ],
      },
      {
        roundNumber: 2,
        matches: [
          {
            matchId: "m2",
            roundNumber: 2,
            participantProfileIds: ["a", "c"],
          },
        ],
      },
    ]);
    expect(r.valid).toBe(true);
  });

  it("rejects non-array", () => {
    const r = validateRoundsStructure("not an array");
    expect(r.valid).toBe(false);
  });

  it("rejects duplicate roundNumbers", () => {
    const r = validateRoundsStructure([
      {roundNumber: 1, matches: []},
      {roundNumber: 1, matches: []},
    ]);
    expect(r.valid).toBe(false);
    expect(r.errors.some((e) => e.includes("duplicate roundNumber")))
      .toBe(true);
  });

  it("rejects roundNumber less than 1", () => {
    const r = validateRoundsStructure([
      {roundNumber: 0, matches: []},
    ]);
    expect(r.valid).toBe(false);
  });

  it("rejects duplicate matchIds across rounds", () => {
    const r = validateRoundsStructure([
      {
        roundNumber: 1,
        matches: [{
          matchId: "m1",
          roundNumber: 1,
          participantProfileIds: ["a", "b"],
        }],
      },
      {
        roundNumber: 2,
        matches: [{
          matchId: "m1",
          roundNumber: 2,
          participantProfileIds: ["a", "b"],
        }],
      },
    ]);
    expect(r.valid).toBe(false);
    expect(r.errors.some((e) => e.includes("duplicate matchId")))
      .toBe(true);
  });

  it("rejects invalid match within round", () => {
    const r = validateRoundsStructure([
      {
        roundNumber: 1,
        matches: [{
          matchId: "m1",
          roundNumber: 1,
          participantProfileIds: ["a", "b"],
          winnerProfileIds: ["a"],
          loserProfileIds: ["a"],
        }],
      },
    ]);
    expect(r.valid).toBe(false);
    expect(
      r.errors.some((e) => e.includes("WINNER_LOSER_OVERLAP"))
    ).toBe(true);
  });
});
