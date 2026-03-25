import {validateRoundsStructure} from "./bracketModel.js";
import {
  deterministicShuffleProfileIds,
  buildRandomSeededRounds,
  randomSeedCanonicalString,
} from "./bracketRandomSeed.js";

describe("deterministicShuffleProfileIds", () => {
  const ids = ["a", "b", "c", "d"];

  it("is stable for same bracketId and ids", () => {
    const a = deterministicShuffleProfileIds("bracket_1", ids);
    const b = deterministicShuffleProfileIds("bracket_1", ids);
    expect(a).toEqual(b);
    expect(new Set(a)).toEqual(new Set(ids));
    expect(a.length).toBe(4);
  });

  it("differs when bracketId changes", () => {
    const x = deterministicShuffleProfileIds("bracket_a", ids);
    const y = deterministicShuffleProfileIds("bracket_b", ids);
    expect(x).not.toEqual(y);
  });

  it("depends on participant array order in canonical string", () => {
    const u1 = deterministicShuffleProfileIds("x", ["a", "b", "c"]);
    const u2 = deterministicShuffleProfileIds("x", ["c", "b", "a"]);
    expect(u1).not.toEqual(u2);
  });
});

describe("buildRandomSeededRounds", () => {
  it("produces valid rounds for 4 players teamSize 1", () => {
    const rounds = buildRandomSeededRounds(
      "b_rand",
      ["a", "b", "c", "d"],
      1
    );
    expect(rounds.length).toBeGreaterThan(0);
    expect(validateRoundsStructure(rounds).valid).toBe(true);
  });

  it("produces valid rounds for 4 players teamSize 2", () => {
    const rounds = buildRandomSeededRounds(
      "b_rand2",
      ["a", "b", "c", "d"],
      2
    );
    const r1 = rounds.find((r) => r.roundNumber === 1);
    expect(r1?.matches[0].participantProfileIds).toHaveLength(4);
    expect(validateRoundsStructure(rounds).valid).toBe(true);
  });

  it("is deterministic for same inputs", () => {
    const ids = ["p1", "p2", "p3", "p4"];
    const r1 = buildRandomSeededRounds("same", ids, 1);
    const r2 = buildRandomSeededRounds("same", ids, 1);
    expect(r1).toEqual(r2);
  });
});

describe("randomSeedCanonicalString", () => {
  it("joins bracket id and ids", () => {
    expect(
      randomSeedCanonicalString("bid", ["x", "y"])
    ).toBe("bid|x|y");
  });
});
