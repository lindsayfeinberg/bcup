import {sortUniqueProfileIds} from "./brackets.js";

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
