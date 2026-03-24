import {
  compareParticipantsForOddsSeeding,
  sortParticipantsForOddsSeeding,
  SeedingParticipant,
  H2HMap,
} from "./oddsSeedingCompare.js";

const base: SeedingParticipant = {
  profileId: "uid_a",
  createdAtMs: 1000,
  overallOdds: 0.5,
  overallGamesPlayed: 4,
  communityOdds: 0.5,
  communityGamesPlayed: 2,
};

const clone = (
  overrides: Partial<SeedingParticipant>
): SeedingParticipant => ({...base, ...overrides});

describe("compareParticipantsForOddsSeeding", () => {
  // api-contracts acceptance example:
  // A: wins=2, games=4 → 0.5 | B: wins=1, games=2 → 0.5
  // → A wins (more games)
  it("step 2: same effective odds, more games wins (overall path)", () => {
    const a = clone({
      profileId: "uid_a",
      communityGamesPlayed: 0,
      overallOdds: 0.5,
      overallGamesPlayed: 4,
    });
    const b = clone({
      profileId: "uid_b",
      communityGamesPlayed: 0,
      overallOdds: 0.5,
      overallGamesPlayed: 2,
    });
    expect(compareParticipantsForOddsSeeding(a, b)).toBeLessThan(0);
  });

  it("step 2: same effective odds, more communityGamesPlayed wins", () => {
    const a = clone({
      profileId: "uid_a",
      communityOdds: 0.5,
      communityGamesPlayed: 4,
    });
    const b = clone({
      profileId: "uid_b",
      communityOdds: 0.5,
      communityGamesPlayed: 2,
    });
    expect(compareParticipantsForOddsSeeding(a, b)).toBeLessThan(0);
  });

  it("step 1: higher odds sorts first", () => {
    const a = clone({profileId: "uid_a", communityOdds: 0.8});
    const b = clone({profileId: "uid_b", communityOdds: 0.5});
    expect(compareParticipantsForOddsSeeding(a, b)).toBeLessThan(0);
  });

  // api-contracts: same odds, same games → earlier createdAt wins
  it("step 4: same odds and games, earlier createdAt wins", () => {
    const a = clone({
      profileId: "uid_a",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    const b = clone({
      profileId: "uid_b",
      createdAtMs: 2000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    expect(compareParticipantsForOddsSeeding(a, b)).toBeLessThan(0);
  });

  // api-contracts: full tie on 1-4 → lower profileId wins
  it("step 5: full tie, lexicographic profileId wins", () => {
    const a = clone({
      profileId: "uid_a",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    const b = clone({
      profileId: "uid_b",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    expect(compareParticipantsForOddsSeeding(a, b)).toBeLessThan(0);
  });

  it("step 3: h2h breaks tie when odds and games match", () => {
    const a = clone({
      profileId: "uid_a",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 4,
      overallOdds: 0.5,
    });
    const b = clone({
      profileId: "uid_b",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 4,
      overallOdds: 0.5,
    });
    const h2h: H2HMap = new Map([
      ["uid_a", new Map([["uid_b", 3]])],
      ["uid_b", new Map([["uid_a", 1]])],
    ]);
    expect(
      compareParticipantsForOddsSeeding(a, b, h2h)
    ).toBeLessThan(0);
  });

  it("h2h missing entry treated as tie, falls to step 4", () => {
    const a = clone({
      profileId: "uid_a",
      createdAtMs: 1000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    const b = clone({
      profileId: "uid_b",
      createdAtMs: 2000,
      communityGamesPlayed: 0,
      overallGamesPlayed: 2,
      overallOdds: 0.5,
    });
    const h2h: H2HMap = new Map();
    expect(
      compareParticipantsForOddsSeeding(a, b, h2h)
    ).toBeLessThan(0);
  });
});

describe("sortParticipantsForOddsSeeding", () => {
  it("sorts best seed first", () => {
    const a = clone({
      profileId: "uid_a",
      communityGamesPlayed: 0,
      overallOdds: 0.5,
      overallGamesPlayed: 4,
    });
    const b = clone({
      profileId: "uid_b",
      communityGamesPlayed: 0,
      overallOdds: 0.8,
      overallGamesPlayed: 2,
    });
    const c = clone({
      profileId: "uid_c",
      communityGamesPlayed: 0,
      overallOdds: 0.3,
      overallGamesPlayed: 6,
    });
    const sorted = sortParticipantsForOddsSeeding([a, b, c]);
    expect(sorted.map((p) => p.profileId)).toEqual([
      "uid_b",
      "uid_a",
      "uid_c",
    ]);
  });
});
