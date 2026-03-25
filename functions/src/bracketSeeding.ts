import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {
  SeedingParticipant,
  H2HMap,
  sortParticipantsForOddsSeeding,
} from "./oddsSeedingCompare.js";
import {BracketRound, BracketMatch} from "./bracketModel.js";

const db = admin.firestore();

// MARK: - Eligibility

interface EligibleLogData {
  participantProfileIds: string[];
  winnerProfileIds: string[];
  loserProfileIds: string[];
}

/**
 * Returns true if a raw Firestore doc is an eligible game log.
 * @param {Record<string, unknown>} d Raw doc data.
 * @return {boolean}
 */
function isEligibleLog(d: Record<string, unknown>): boolean {
  const p = d.participantProfileIds as string[] | undefined;
  const w = d.winnerProfileIds as string[] | undefined;
  const l = d.loserProfileIds as string[] | undefined;
  return (
    Array.isArray(p) && p.length > 0 &&
    Array.isArray(w) && w.length > 0 &&
    Array.isArray(l) && l.length > 0
  );
}

// MARK: - Profile + membership data loading

interface ParticipantOddsData {
  profileId: string;
  overallOdds: number;
  overallGamesPlayed: number;
  communityOdds: number;
  communityGamesPlayed: number;
  createdAtMs: number;
}

/**
 * Loads profile and membership odds data for all participants.
 * Tolerates missing docs with safe defaults (0 for odds/games,
 * Date.now() for createdAt).
 * @param {string[]} profileIds Participant profile IDs.
 * @param {string} communityId Community scope for membership read.
 * @return {Promise<ParticipantOddsData[]>}
 */
export async function loadParticipantOddsData(
  profileIds: string[],
  communityId: string
): Promise<ParticipantOddsData[]> {
  const profileRefs = profileIds.map((id) =>
    db.collection("profiles").doc(id)
  );
  const membershipRefs = profileIds.map((id) =>
    db.collection("memberships").doc(`${communityId}_${id}`)
  );

  const [profileSnaps, membershipSnaps] = await Promise.all([
    db.getAll(...profileRefs),
    db.getAll(...membershipRefs),
  ]);

  return profileIds.map((profileId, i) => {
    const pd = profileSnaps[i].data() ?? {};
    const md = membershipSnaps[i].data() ?? {};

    const overallOdds =
      (pd["overallOdds"] as number | undefined) ?? 0;
    const overallGamesPlayed =
      (pd["overallGamesPlayed"] as number | undefined) ?? 0;
    const createdAtTs = pd["createdAt"] as
      | admin.firestore.Timestamp
      | undefined;
    const createdAtMs = createdAtTs ?
      createdAtTs.toMillis() :
      Date.now();

    const communityOdds =
      (md["communityOdds"] as number | undefined) ?? 0;
    const communityGamesPlayed =
      (md["communityGamesPlayed"] as number | undefined) ?? 0;

    return {
      profileId,
      overallOdds,
      overallGamesPlayed,
      communityOdds,
      communityGamesPlayed,
      createdAtMs,
    };
  });
}

// MARK: - H2H map

/**
 * Builds a head-to-head win map from all eligible game logs
 * in the community.
 * h2h.get(a).get(b) = number of times A beat B.
 * V1 definition: A beat B if A is in winnerProfileIds and B is
 * in loserProfileIds in the same eligible log.
 * @param {string} communityId Community scope.
 * @param {string[]} profileIds Participants to track.
 * @return {Promise<H2HMap>}
 */
export async function buildH2HMap(
  communityId: string,
  profileIds: string[]
): Promise<H2HMap> {
  const snap = await db
    .collection("gameLogs")
    .where("communityId", "==", communityId)
    .get();

  const profileSet = new Set(profileIds);
  const h2h: H2HMap = new Map();

  for (const doc of snap.docs) {
    const d = doc.data() as Record<string, unknown>;
    if (!isEligibleLog(d)) continue;
    const log = d as unknown as EligibleLogData;

    const winners = log.winnerProfileIds.filter((id) =>
      profileSet.has(id)
    );
    const losers = log.loserProfileIds.filter((id) =>
      profileSet.has(id)
    );

    for (const w of winners) {
      for (const l of losers) {
        if (w === l) continue;
        if (!h2h.has(w)) h2h.set(w, new Map());
        const wMap = h2h.get(w);
        if (wMap) wMap.set(l, (wMap.get(l) ?? 0) + 1);
      }
    }
  }

  logger.debug("buildH2HMap: complete", {
    communityId,
    logCount: snap.docs.length,
  });

  return h2h;
}

// MARK: - Team chunking

/**
 * Chunks an ordered seed list into teams of teamSize.
 * The last team may be smaller if N % teamSize !== 0.
 * The smaller (last) team receives a bye and auto-advances.
 * @param {string[]} seededIds Ordered profile IDs (best first).
 * @param {number} teamSize Players per team.
 * @return {Array<string[]>} Array of teams, each an array of profileIds.
 */
export function chunkIntoTeams(
  seededIds: string[],
  teamSize: number
): string[][] {
  const teams: string[][] = [];
  for (let i = 0; i < seededIds.length; i += teamSize) {
    teams.push(seededIds.slice(i, i + teamSize));
  }
  return teams;
}

// MARK: - Bye padding

/**
 * Returns the smallest power of 2 >= n.
 * @param {number} n Input number.
 * @return {number} Next power of 2.
 */
export function nextPowerOfTwo(n: number): number {
  if (n <= 1) return 1;
  return Math.pow(2, Math.ceil(Math.log2(n)));
}

/**
 * Pads a teams array to the next power-of-two size with null
 * bye slots. Best seeds get byes first.
 * Example: 6 teams pads to 8 with 2 bye slots at front.
 * @param {Array} teams Ordered teams array.
 * @return {Array} Padded teams with null bye slots.
 */
export function padTeamsWithByes(
  teams: string[][]
): Array<string[] | null> {
  const target = nextPowerOfTwo(teams.length);
  const byeCount = target - teams.length;

  // Insert bye slots at the front (best seeds get byes)
  const byes: null[] = Array(byeCount).fill(null);
  return [...byes, ...teams];
}

// MARK: - Match ID generation

/**
 * Generates a stable match ID from round and position.
 * @param {string} bracketId Parent bracket ID.
 * @param {number} roundNumber 1-based round number.
 * @param {number} matchIndex 0-based match index in the round.
 * @return {string} Stable match ID.
 */
export function makeMatchId(
  bracketId: string,
  roundNumber: number,
  matchIndex: number
): string {
  return `${bracketId}_r${roundNumber}_m${matchIndex}`;
}

// MARK: - Full bracket generation

/**
 * Generates a full single-elimination bracket tree.
 * Round 1 has real matches. Later rounds have placeholder matches
 * with empty participantProfileIds and feederMatchIds for T10.7.
 * @param {string} bracketId Parent bracket ID for matchIds.
 * @param {Array} teams Ordered teams, best seed first.
 * @param {number} _teamSize Players per team (reserved).
 * @return {Array} Full bracket rounds.
 */
export function generateBracketRounds(
  bracketId: string,
  teams: string[][],
): BracketRound[] {
  // Pad teams to power-of-two with bye slots
  const paddedSlots = padTeamsWithByes(teams);
  const totalSlots = paddedSlots.length;
  const totalRounds = Math.log2(totalSlots);

  // slot[i] holds the current occupant of bracket slot i
  // null = bye slot, string[] = team profileIds
  // We track the "advancing" team for each slot across rounds
  const slotTeams: Array<string[] | null> = [...paddedSlots];

  const allRounds: BracketRound[] = [];

  for (let r = 1; r <= totalRounds; r++) {
    const matchesInRound = totalSlots / Math.pow(2, r);
    const matches: BracketMatch[] = [];

    for (let m = 0; m < matchesInRound; m++) {
      const slot1 = m * 2;
      const slot2 = m * 2 + 1;
      const team1 = slotTeams[slot1];
      const team2 = slotTeams[slot2];
      const matchId = makeMatchId(bracketId, r, m);

      if (r === 1) {
        if (team1 === null && team2 !== null) {
          // team2 gets bye — advance team2, no match written
          slotTeams[m] = team2;
          continue;
        } else if (team2 === null && team1 !== null) {
          // team1 gets bye — advance team1, no match written
          slotTeams[m] = team1;
          continue;
        } else if (team1 !== null && team2 !== null) {
          // Real round 1 match
          matches.push({
            matchId,
            roundNumber: r,
            participantProfileIds: [...team1, ...team2],
          } as BracketMatch);
          // Winner slot TBD — leave null for now
          slotTeams[m] = null;
        }
      } else {
        // Later rounds: placeholder match
        const feeder1 = makeMatchId(bracketId, r - 1, slot1);
        const feeder2 = makeMatchId(bracketId, r - 1, slot2);
        const match: BracketMatch = {
          matchId,
          roundNumber: r,
          participantProfileIds: [],
          feederMatchIds: [feeder1, feeder2],
        };
        matches.push(match);
        slotTeams[m] = null;
      }
    }

    if (matches.length > 0) {
      allRounds.push({roundNumber: r, matches});
    }
  }

  return allRounds;
}

// MARK: - Top-level seeding entry point

/**
 * Builds seeded bracket rounds for COMMUNITY_ODDS method.
 * Loads profile/membership data, builds H2H map, sorts seeds,
 * chunks into teams, pads with byes, generates full tree.
 * @param {string} bracketId Bracket document ID.
 * @param {string[]} participantProfileIds All participant IDs.
 * @param {string} communityId Community scope.
 * @param {number} teamSize Players per team.
 * @return {Promise<BracketRound[]>} Generated rounds.
 */
export async function buildCommunityOddsRounds(
  bracketId: string,
  participantProfileIds: string[],
  communityId: string,
  teamSize: number
): Promise<BracketRound[]> {
  logger.info("buildCommunityOddsRounds: start", {
    bracketId,
    participantCount: participantProfileIds.length,
    communityId,
    teamSize,
  });

  // Load odds data and H2H in parallel
  const [oddsData, h2h] = await Promise.all([
    loadParticipantOddsData(participantProfileIds, communityId),
    buildH2HMap(communityId, participantProfileIds),
  ]);

  const seedingParticipants: SeedingParticipant[] = oddsData.map(
    (d) => ({
      profileId: d.profileId,
      createdAtMs: d.createdAtMs,
      overallOdds: d.overallOdds,
      overallGamesPlayed: d.overallGamesPlayed,
      communityOdds: d.communityOdds,
      communityGamesPlayed: d.communityGamesPlayed,
    })
  );

  const sorted = sortParticipantsForOddsSeeding(
    seedingParticipants,
    h2h
  );
  const seededIds = sorted.map((p) => p.profileId);

  logger.info("buildCommunityOddsRounds: seeds resolved", {
    bracketId,
    seededIds,
  });

  const teams = chunkIntoTeams(seededIds, teamSize);
  const rounds = generateBracketRounds(bracketId, teams);

  logger.info("buildCommunityOddsRounds: rounds generated", {
    bracketId,
    roundCount: rounds.length,
    round1Matches: rounds[0]?.matches.length ?? 0,
  });

  return rounds;
}
