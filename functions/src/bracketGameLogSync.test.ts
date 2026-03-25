import type {BracketDocument} from "./bracketModel.js";
import {applyGameLogOutcomeToBracketDoc} from "./bracketGameLogSync.js";

function makeBracketDoc(params: {
  bracketId: string;
  communityId: string;
  status: "DRAFT" | "ACTIVE" | "COMPLETE";
  teamSize: number;
  rounds: BracketDocument["rounds"];
}): BracketDocument {
  return {
    id: params.bracketId,
    communityId: params.communityId,
    participantProfileIds: [],
    seedMethod: "RANDOM",
    teamSize: params.teamSize,
    status: params.status,
    rounds: params.rounds,
    createdAt: "ts" as unknown,
    updatedAt: "ts" as unknown,
  };
}

describe("applyGameLogOutcomeToBracketDoc", () => {
  it("no fields / unknown matchId => no-op", () => {
    const bracket = makeBracketDoc({
      bracketId: "br1",
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId: "br1_r1_m0",
              roundNumber: 1,
              participantProfileIds: ["a", "b"],
            },
          ],
        },
      ],
    });

    const {updatedBracket, result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: "",
        communityId: "c1",
        participantProfileIds: ["a", "b"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["b"],
      }
    );

    expect(result.didUpdate).toBe(false);
    expect(updatedBracket).toEqual(bracket);
  });

  it("happy path: 1v1 win/lose writes outcome + completes bracket", () => {
    const bracketId = "br1";
    const matchId = "br1_r1_m0";
    const bracket = makeBracketDoc({
      bracketId,
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId,
              roundNumber: 1,
              participantProfileIds: ["a", "b"],
            },
          ],
        },
      ],
    });

    const {updatedBracket, result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: matchId,
        communityId: "c1",
        participantProfileIds: ["a", "b"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["b"],
      }
    );

    expect(result.didUpdate).toBe(true);
    const updatedMatch = updatedBracket.rounds[0].matches[0];
    expect(updatedMatch.winnerProfileIds).toEqual(["a"]);
    expect(updatedMatch.loserProfileIds).toEqual(["b"]);
    expect(updatedBracket.status).toBe("COMPLETE");
  });

  it("idempotent: second run is a no-op when match already has outcome keys", () => {
    const bracketId = "br1";
    const matchId = "br1_r1_m0";
    const bracket = makeBracketDoc({
      bracketId,
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId,
              roundNumber: 1,
              participantProfileIds: ["a", "b"],
              winnerProfileIds: ["a"],
              loserProfileIds: ["b"],
            },
          ],
        },
      ],
    });

    const {result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: matchId,
        communityId: "c1",
        participantProfileIds: ["a", "b"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["b"],
      }
    );

    expect(result.didUpdate).toBe(false);
  });

  it("wrong community => no-op", () => {
    const bracket = makeBracketDoc({
      bracketId: "br1",
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId: "br1_r1_m0",
              roundNumber: 1,
              participantProfileIds: ["a", "b"],
            },
          ],
        },
      ],
    });

    const {result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: "br1_r1_m0",
        communityId: "c2",
        participantProfileIds: ["a", "b"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["b"],
      }
    );

    expect(result.didUpdate).toBe(false);
  });

  it("invalid participants (winner not in match) => no-op", () => {
    const bracket = makeBracketDoc({
      bracketId: "br1",
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId: "br1_r1_m0",
              roundNumber: 1,
              participantProfileIds: ["a", "b"],
            },
          ],
        },
      ],
    });

    const {result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: "br1_r1_m0",
        communityId: "c1",
        participantProfileIds: ["a", "c"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["c"],
      }
    );

    expect(result.didUpdate).toBe(false);
  });

  it("rejects placeholder match updates (feederMatchIds present)", () => {
    const bracket = makeBracketDoc({
      bracketId: "br1",
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [],
        },
        {
          roundNumber: 2,
          matches: [
            {
              matchId: "br1_r2_m0",
              roundNumber: 2,
              participantProfileIds: [],
              feederMatchIds: ["br1_r1_m0", "br1_r1_m1"],
            },
          ],
        },
      ],
    });

    const {result} = applyGameLogOutcomeToBracketDoc(
      bracket,
      {
        bracketMatchId: "br1_r2_m0",
        communityId: "c1",
        participantProfileIds: ["a", "b"],
        winnerProfileIds: ["a"],
        loserProfileIds: ["b"],
      }
    );

    expect(result.didUpdate).toBe(false);
  });

  it("advances winners into next round when both feeder matches are played", () => {
    const bracketId = "br1";
    const m0 = "br1_r1_m0";
    const m1 = "br1_r1_m1";
    const finalM = "br1_r2_m0";

    const bracket = makeBracketDoc({
      bracketId,
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {matchId: m0, roundNumber: 1, participantProfileIds: ["a", "b"]},
            {matchId: m1, roundNumber: 1, participantProfileIds: ["c", "d"]},
          ],
        },
        {
          roundNumber: 2,
          matches: [
            {
              matchId: finalM,
              roundNumber: 2,
              participantProfileIds: [],
              feederMatchIds: [m0, m1],
            },
          ],
        },
      ],
    });

    const afterM0 = applyGameLogOutcomeToBracketDoc(bracket, {
      bracketMatchId: m0,
      communityId: "c1",
      participantProfileIds: ["a", "b"],
      winnerProfileIds: ["a"],
      loserProfileIds: ["b"],
    });

    expect(afterM0.result.didUpdate).toBe(true);
    const placeholderAfterM0 = afterM0.updatedBracket.rounds[1].matches[0];
    // Placeholder participants get incrementally filled when only one feeder is played.
    expect(placeholderAfterM0.participantProfileIds).toEqual(["a"]);
    expect(placeholderAfterM0.feederMatchIds).toEqual([m0, m1]);
    expect(afterM0.updatedBracket.status).toBe("ACTIVE");

    const afterM1 = applyGameLogOutcomeToBracketDoc(afterM0.updatedBracket, {
      bracketMatchId: m1,
      communityId: "c1",
      participantProfileIds: ["c", "d"],
      winnerProfileIds: ["c"],
      loserProfileIds: ["d"],
    });

    expect(afterM1.result.didUpdate).toBe(true);
    const finalScheduled = afterM1.updatedBracket.rounds[1].matches[0];
    expect(finalScheduled.participantProfileIds).toEqual(["a", "c"]);
    expect(finalScheduled.feederMatchIds).toBeUndefined();
    expect(afterM1.updatedBracket.status).toBe("ACTIVE");

    const afterFinal = applyGameLogOutcomeToBracketDoc(afterM1.updatedBracket, {
      bracketMatchId: finalM,
      communityId: "c1",
      participantProfileIds: ["a", "c"],
      winnerProfileIds: ["a"],
      loserProfileIds: ["c"],
    });

    expect(afterFinal.result.didUpdate).toBe(true);
    const finalMatch = afterFinal.updatedBracket.rounds[1].matches[0];
    expect(finalMatch.winnerProfileIds).toEqual(["a"]);
    expect(finalMatch.loserProfileIds).toEqual(["c"]);
    expect(afterFinal.updatedBracket.status).toBe("COMPLETE");
  });

  it("completes placeholder participants with prefilled bye even if one feeder match is missing", () => {
    const bracketId = "br1";
    const byeFeederMatchId = "br1_r1_m0"; // missing from rounds[0].matches
    const realFeederMatchId = "br1_r1_m1";
    const placeholderMatchId = "br1_r2_m0";

    const bracket = makeBracketDoc({
      bracketId,
      communityId: "c1",
      status: "ACTIVE",
      teamSize: 1,
      rounds: [
        {
          roundNumber: 1,
          matches: [
            {
              matchId: realFeederMatchId,
              roundNumber: 1,
              participantProfileIds: ["c", "d"],
            },
          ],
        },
        {
          roundNumber: 2,
          matches: [
            {
              matchId: placeholderMatchId,
              roundNumber: 2,
              participantProfileIds: ["b"], // prefilled bye-side winner
              feederMatchIds: [byeFeederMatchId, realFeederMatchId],
            },
          ],
        },
      ],
    });

    const afterRealFeeder = applyGameLogOutcomeToBracketDoc(bracket, {
      bracketMatchId: realFeederMatchId,
      communityId: "c1",
      participantProfileIds: ["c", "d"],
      winnerProfileIds: ["c"],
      loserProfileIds: ["d"],
    });

    expect(afterRealFeeder.result.didUpdate).toBe(true);
    const updatedPlaceholder = afterRealFeeder.updatedBracket.rounds[1]
      .matches[0];
    expect(updatedPlaceholder.participantProfileIds).toEqual(["b", "c"]);
    // When both participant sides are known, the placeholder converts to a scheduled match.
    expect(updatedPlaceholder.feederMatchIds).toBeUndefined();
    expect(afterRealFeeder.updatedBracket.status).toBe("ACTIVE");
  });
});

