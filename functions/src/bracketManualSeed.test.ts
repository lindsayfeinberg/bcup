import {
  validatePermutation,
  validateManualTeams,
  expectedTeamSizes,
  buildManualRoundsFromTeams,
} from "./bracketManualSeed.js";
import {validateRoundsStructure} from "./bracketModel.js";

describe("validatePermutation", () => {
  const expected = ["uid_a", "uid_b", "uid_c", "uid_d"];

  it("accepts valid permutation", () => {
    const err = validatePermutation(
      ["uid_c", "uid_a", "uid_d", "uid_b"],
      expected
    );
    expect(err).toBeNull();
  });

  it("rejects wrong length — too few", () => {
    const err = validatePermutation(
      ["uid_a", "uid_b"],
      expected
    );
    expect(err).not.toBeNull();
    expect(err).toContain("Expected 4");
  });

  it("rejects wrong length — too many", () => {
    const err = validatePermutation(
      ["uid_a", "uid_b", "uid_c", "uid_d", "uid_e"],
      expected
    );
    expect(err).not.toBeNull();
  });

  it("rejects duplicate ids", () => {
    const err = validatePermutation(
      ["uid_a", "uid_a", "uid_c", "uid_d"],
      expected
    );
    expect(err).not.toBeNull();
    expect(err).toContain("Duplicate");
  });

  it("rejects unknown id", () => {
    const err = validatePermutation(
      ["uid_a", "uid_b", "uid_c", "uid_z"],
      expected
    );
    expect(err).not.toBeNull();
    expect(err).toContain("Unknown");
  });

  it("accepts same order as expected", () => {
    expect(validatePermutation(expected, expected)).toBeNull();
  });
});

describe("expectedTeamSizes", () => {
  it("4 players teamSize 2 → two full teams", () => {
    expect(expectedTeamSizes(4, 2)).toEqual([2, 2]);
  });

  it("5 players teamSize 2 → 2,2,1", () => {
    expect(expectedTeamSizes(5, 2)).toEqual([2, 2, 1]);
  });

  it("4 players teamSize 1 → four singletons", () => {
    expect(expectedTeamSizes(4, 1)).toEqual([1, 1, 1, 1]);
  });
});

describe("validateManualTeams", () => {
  const four = ["uid_a", "uid_b", "uid_c", "uid_d"];

  it("accepts valid 2v2 partition", () => {
    expect(
      validateManualTeams(
        [
          ["uid_a", "uid_b"],
          ["uid_c", "uid_d"],
        ],
        four,
        2
      )
    ).toBeNull();
  });

  it("rejects wrong team count", () => {
    const err = validateManualTeams(
      [[...four]],
      four,
      2
    );
    expect(err).toContain("Expected 2 teams");
  });

  it("rejects wrong row size", () => {
    const err = validateManualTeams(
      [
        ["uid_a"],
        ["uid_b", "uid_c", "uid_d"],
      ],
      four,
      2
    );
    expect(err).toContain("Team 1 must have 2 players");
  });

  it("rejects duplicate across teams", () => {
    const err = validateManualTeams(
      [
        ["uid_a", "uid_b"],
        ["uid_b", "uid_c"],
      ],
      four,
      2
    );
    expect(err).not.toBeNull();
    expect(err).toContain("Duplicate");
  });
});

describe("buildManualRoundsFromTeams", () => {
  it("produces valid rounds for 4 singleton teams teamSize 1", () => {
    const rounds = buildManualRoundsFromTeams("b1", [
      ["uid_a"],
      ["uid_b"],
      ["uid_c"],
      ["uid_d"],
    ]);
    expect(rounds.length).toBeGreaterThan(0);
    const result = validateRoundsStructure(rounds);
    expect(result.valid).toBe(true);
  });

  it("bracket order — first match pairs team1 vs team2", () => {
    const rounds = buildManualRoundsFromTeams("b1", [
      ["uid_1"],
      ["uid_2"],
      ["uid_3"],
      ["uid_4"],
    ]);
    const r1 = rounds.find((r) => r.roundNumber === 1);
    expect(r1?.matches[0].participantProfileIds).toContain("uid_1");
    expect(r1?.matches[0].participantProfileIds).toContain("uid_2");
  });

  it("2v2 produces 4-participant first match", () => {
    const rounds = buildManualRoundsFromTeams("b1", [
      ["a", "b"],
      ["c", "d"],
    ]);
    const r1 = rounds.find((r) => r.roundNumber === 1);
    expect(
      r1?.matches[0].participantProfileIds
    ).toHaveLength(4);
    const result = validateRoundsStructure(rounds);
    expect(result.valid).toBe(true);
  });
});
