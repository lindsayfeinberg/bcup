import {validateRoundOneCoversParticipants} from "./bracketModel.js";
import type {BracketRound} from "./bracketModel.js";

describe("validateRoundOneCoversParticipants", () => {
  it("accepts when round1 union matches roster", () => {
    const rounds: BracketRound[] = [
      {
        roundNumber: 1,
        matches: [
          {
            matchId: "b_r1_m0",
            roundNumber: 1,
            participantProfileIds: ["a", "b"],
            winnerProfileIds: ["a", "b"],
          },
          {
            matchId: "b_r1_m1",
            roundNumber: 1,
            participantProfileIds: ["c", "d", "e"],
          },
        ],
      },
    ];
    const r = validateRoundOneCoversParticipants(
      rounds,
      ["a", "b", "c", "d", "e"]
    );
    expect(r.valid).toBe(true);
    expect(r.errors).toEqual([]);
  });

  it("rejects when a roster member is missing from round 1", () => {
    const rounds: BracketRound[] = [
      {
        roundNumber: 1,
        matches: [
          {
            matchId: "b_r1_m0",
            roundNumber: 1,
            participantProfileIds: ["a", "b"],
          },
        ],
      },
    ];
    const r = validateRoundOneCoversParticipants(rounds, ["a", "b", "c"]);
    expect(r.valid).toBe(false);
    expect(r.errors.some((e) => e.includes("missing participant"))).toBe(
      true
    );
  });

  it("skips validation when rounds empty (MANUAL draft)", () => {
    const r = validateRoundOneCoversParticipants([], ["a", "b"]);
    expect(r.valid).toBe(true);
  });
});
