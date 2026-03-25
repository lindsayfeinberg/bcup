import {createHash} from "crypto";
import {chunkIntoTeams, generateBracketRounds} from "./bracketSeeding.js";
import {BracketRound} from "./bracketModel.js";

/**
 * Canonical string for RANDOM seeding: bracket id + sorted participant list.
 * `participantProfileIds` must already be sorted (e.g. sortUniqueProfileIds).
 * @param {string} bracketId Firestore bracket document id.
 * @param {Array<string>} participantProfileIds Sorted unique profile ids.
 * @return {string} Canonical UTF-8 string.
 */
export function randomSeedCanonicalString(
  bracketId: string,
  participantProfileIds: string[]
): string {
  return `${bracketId}|${participantProfileIds.join("|")}`;
}

/**
 * Derives a 32-bit PRNG seed from SHA-256(canonical).
 * @param {Buffer} digest 32-byte SHA-256 digest.
 * @return {number} Unsigned 32-bit seed.
 */
export function seedFromSha256Digest(digest: Buffer): number {
  let s = 0;
  for (let i = 0; i < 32; i += 4) {
    s ^= digest.readUInt32LE(i);
  }
  return s >>> 0;
}

/**
 * Mulberry32 PRNG (public domain). Returns floats in [0, 1).
 * @param {number} seed Unsigned 32-bit seed.
 * @return {function(): number} Next random in [0, 1).
 */
export function mulberry32(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Deterministic shuffle: same bracketId + same sorted participant list
 * always yields the same order (Fisher–Yates with Mulberry32 keyed by
 * SHA-256 of randomSeedCanonicalString).
 * @param {string} bracketId Firestore bracket document id.
 * @param {Array<string>} participantProfileIds Sorted unique profile ids.
 * @return {Array<string>} Shuffled copy (new array).
 */
export function deterministicShuffleProfileIds(
  bracketId: string,
  participantProfileIds: string[]
): string[] {
  const canonical = randomSeedCanonicalString(
    bracketId,
    participantProfileIds
  );
  const digest = createHash("sha256").update(canonical, "utf8").digest();
  const seed = seedFromSha256Digest(digest);
  const rand = mulberry32(seed);
  const arr = [...participantProfileIds];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    const tmp = arr[i];
    arr[i] = arr[j];
    arr[j] = tmp;
  }
  return arr;
}

/**
 * Builds single-elimination rounds from a deterministic random seed order.
 * Callers must pass **lexicographically sorted** unique ids (same as
 * sortUniqueProfileIds) so the canonical string matches stored participants.
 * @param {string} bracketId Parent bracket id for match ids.
 * @param {Array<string>} participantProfileIds Sorted unique profile ids.
 * @param {number} teamSize Players per side.
 * @return {Array<BracketRound>} Full bracket rounds.
 */
export function buildRandomSeededRounds(
  bracketId: string,
  participantProfileIds: string[],
  teamSize: number
): BracketRound[] {
  const shuffled = deterministicShuffleProfileIds(
    bracketId,
    participantProfileIds
  );
  const teams = chunkIntoTeams(shuffled, teamSize);
  return generateBracketRounds(bracketId, teams);
}
