import {
  sortUniqueProfileIds,
  parseBracketGameType,
  parseBracketCallableTeamSize,
  extractProfileIdFromMembershipData,
} from "./brackets.js";

describe("sortUniqueProfileIds", () => {
  it("deduplicates and sorts lexicographically", () => {
    const result = sortUniqueProfileIds([
      "uid_c", "uid_a", "uid_b", "uid_a",
    ]);
    expect(result).toEqual(["uid_a", "uid_b", "uid_c"]);
  });

  it("returns empty array for empty input", () => {
    expect(sortUniqueProfileIds([])).toEqual([]);
  });

  it("handles single entry", () => {
    expect(sortUniqueProfileIds(["uid_a"])).toEqual(["uid_a"]);
  });

  it("is stable — same input always same output", () => {
    const a = sortUniqueProfileIds(["uid_z", "uid_a"]);
    const b = sortUniqueProfileIds(["uid_z", "uid_a"]);
    expect(a).toEqual(b);
  });
});

describe("parseBracketGameType", () => {
  it("defaults invalid or missing to PONG", () => {
    expect(parseBracketGameType(undefined)).toBe("PONG");
    expect(parseBracketGameType(null)).toBe("PONG");
    expect(parseBracketGameType("")).toBe("PONG");
    expect(parseBracketGameType("  ")).toBe("PONG");
    expect(parseBracketGameType("NOT_A_GAME")).toBe("PONG");
  });

  it("accepts built-ins and CUSTOM", () => {
    expect(parseBracketGameType("PONG")).toBe("PONG");
    expect(parseBracketGameType(" BEER_BALL ")).toBe("BEER_BALL");
    expect(parseBracketGameType("CUSTOM")).toBe("CUSTOM");
  });
});

describe("extractProfileIdFromMembershipData", () => {
  it("accepts non-empty trimmed strings", () => {
    expect(
      extractProfileIdFromMembershipData({profileId: "  uid_x  "})
    ).toBe("uid_x");
  });

  it("returns null for empty or missing", () => {
    expect(extractProfileIdFromMembershipData({})).toBeNull();
    expect(extractProfileIdFromMembershipData({profileId: ""})).toBeNull();
    expect(extractProfileIdFromMembershipData({profileId: "  "})).toBeNull();
  });

  it("coerces finite numbers to string ids", () => {
    expect(extractProfileIdFromMembershipData({profileId: 42})).toBe("42");
  });
});

describe("parseBracketCallableTeamSize", () => {
  it("accepts integers 1 through 20", () => {
    expect(parseBracketCallableTeamSize(1)).toBe(1);
    expect(parseBracketCallableTeamSize(12)).toBe(12);
    expect(parseBracketCallableTeamSize(20)).toBe(20);
  });

  it("rejects out of range and non-integers", () => {
    expect(() => parseBracketCallableTeamSize(0)).toThrow();
    expect(() => parseBracketCallableTeamSize(21)).toThrow();
    expect(() => parseBracketCallableTeamSize(2.5)).toThrow();
    expect(() => parseBracketCallableTeamSize("x")).toThrow();
  });
});
