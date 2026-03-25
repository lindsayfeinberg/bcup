import {
  chunkIntoTeams,
  nextPowerOfTwo,
  padTeamsWithByes,
  makeMatchId,
  generateBracketRounds,
} from "./bracketSeeding.js";
import {validateRoundsStructure} from "./bracketModel.js";

describe("nextPowerOfTwo", () => {
  it("returns 1 for 1", () => expect(nextPowerOfTwo(1)).toBe(1));
  it("returns 2 for 2", () => expect(nextPowerOfTwo(2)).toBe(2));
  it("returns 4 for 3", () => expect(nextPowerOfTwo(3)).toBe(4));
  it("returns 4 for 4", () => expect(nextPowerOfTwo(4)).toBe(4));
  it("returns 8 for 5", () => expect(nextPowerOfTwo(5)).toBe(8));
  it("returns 8 for 6", () => expect(nextPowerOfTwo(6)).toBe(8));
  it("returns 16 for 9", () => expect(nextPowerOfTwo(9)).toBe(16));
});

describe("chunkIntoTeams", () => {
  it("chunks evenly", () => {
    const r = chunkIntoTeams(["a", "b", "c", "d"], 2);
    expect(r).toEqual([["a", "b"], ["c", "d"]]);
  });

  it("last team is smaller when not divisible", () => {
    const r = chunkIntoTeams(["a", "b", "c", "d", "e"], 2);
    expect(r).toEqual([["a", "b"], ["c", "d"], ["e"]]);
  });

  it("teamSize 1 gives individual teams", () => {
    const r = chunkIntoTeams(["a", "b", "c"], 1);
    expect(r).toEqual([["a"], ["b"], ["c"]]);
  });
});

describe("padTeamsWithByes", () => {
  it("no padding needed for power of 2", () => {
    const teams = [["a", "b"], ["c", "d"]];
    const r = padTeamsWithByes(teams);
    expect(r).toEqual([["a", "b"], ["c", "d"]]);
  });

  it("pads 3 teams to 4 with 1 bye at front", () => {
    const teams = [["a"], ["b"], ["c"]];
    const r = padTeamsWithByes(teams);
    expect(r).toHaveLength(4);
    expect(r[0]).toBeNull();
    expect(r[1]).toEqual(["a"]);
  });

  it("pads 6 teams to 8 with 2 byes distributed", () => {
    const teams = [["a"], ["b"], ["c"], ["d"], ["e"], ["f"]];
    const r = padTeamsWithByes(teams);
    expect(r).toHaveLength(8);
    expect(r[0]).toBeNull();
    expect(r[2]).toBeNull();
    expect(r[1]).toEqual(["a"]);
    expect(r[3]).toEqual(["b"]);
  });
});

describe("makeMatchId", () => {
  it("generates stable id", () => {
    expect(makeMatchId("bracket1", 1, 0)).toBe("bracket1_r1_m0");
    expect(makeMatchId("bracket1", 2, 3)).toBe("bracket1_r2_m3");
  });
});

describe("generateBracketRounds", () => {
  it("2 teams, teamSize 1 — 1 round, 1 match", () => {
    const rounds = generateBracketRounds("b1", [["a"], ["b"]]);
    expect(rounds).toHaveLength(1);
    expect(rounds[0].matches).toHaveLength(1);
    expect(
      rounds[0].matches[0].participantProfileIds
    ).toEqual(["a", "b"]);
    const result = validateRoundsStructure(rounds);
    expect(result.valid).toBe(true);
  });

  it("4 teams, teamSize 1 — 2 rounds", () => {
    const rounds = generateBracketRounds(
      "b1", [["a"], ["b"], ["c"], ["d"]]
    );
    expect(rounds).toHaveLength(2);
    expect(rounds[0].roundNumber).toBe(1);
    expect(rounds[0].matches).toHaveLength(2);
    expect(rounds[1].roundNumber).toBe(2);
    expect(rounds[1].matches).toHaveLength(1);
  });

  it("3 teams — bye is represented as a finalized round-1 bye match", () => {
    const rounds = generateBracketRounds(
      "b1", [["a"], ["b"], ["c"]]
    );
    const r1 = rounds.find((r) => r.roundNumber === 1);
    expect(r1?.matches).toHaveLength(2);

    const matchWithBC = r1?.matches.find((m) =>
      m.participantProfileIds.includes("b") &&
      m.participantProfileIds.includes("c")
    );
    expect(matchWithBC).toBeDefined();

    const byeMatch = r1?.matches.find((m) =>
      m.participantProfileIds.includes("a")
    );
    expect(byeMatch).toBeDefined();
    expect(byeMatch?.winnerProfileIds).toEqual(["a"]);

    const r2 = rounds.find((r) => r.roundNumber === 2);
    expect(r2?.matches).toHaveLength(1);
    // Round-2 placeholder participants get prefilled with the bye-side winner.
    expect(r2?.matches[0].participantProfileIds).toEqual(["a"]);
  });

  it("2v2 match has 4 participants", () => {
    const rounds = generateBracketRounds(
      "b1",
      [["a", "b"], ["c", "d"]]
    );
    expect(
      rounds[0].matches[0].participantProfileIds
    ).toHaveLength(4);
  });

  it("generated rounds pass validateRoundsStructure", () => {
    const rounds = generateBracketRounds(
      "b1", [["a"], ["b"], ["c"], ["d"]]
    );
    const result = validateRoundsStructure(rounds);
    expect(result.valid).toBe(true);
  });
});

const bracketId = "test123";
const teams = [["playerA"], ["playerB"], ["playerC"]];

const rounds = generateBracketRounds(bracketId, teams);

console.log("Round count:", rounds.length);
console.log("Round 1 match count:", rounds[0]?.matches?.length);
console.log("Round 1 matches:", JSON.stringify(rounds[0]?.matches, null, 2));
console.log("Round 2 matches:", JSON.stringify(rounds[1]?.matches, null, 2));
