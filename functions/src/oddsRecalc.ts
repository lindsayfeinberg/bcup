import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

export type GameLogEventKind = "created" | "updated" | "deleted";

export interface OddsRecalcContext {
  gameLogId: string;
  communityId: string | null;
  previousCommunityId: string | null;
  impactedProfileIds: string[];
  kind: GameLogEventKind;
}

/** Matches iOS `GameType` raw values in game logs. */
const KNOWN_GAME_TYPES = [
  "PONG",
  "BEER_BALL",
  "BATTLE_PONG",
  "BASEBALL",
  "CROSSFIRE",
] as const;

type KnownGameType = (typeof KNOWN_GAME_TYPES)[number];

interface EligibleLog {
  participantProfileIds: string[];
  winnerProfileIds: string[];
}

/**
 * Returns true if a Firestore doc is an eligible game log
 * per the api-contracts definition.
 * @param {Record<string, unknown>} data Raw Firestore doc data.
 * @return {boolean}
 */
function isEligible(data: Record<string, unknown>): boolean {
  const participants =
    data.participantProfileIds as string[] | undefined;
  const winners =
    data.winnerProfileIds as string[] | undefined;
  const losers =
    data.loserProfileIds as string[] | undefined;
  return (
    Array.isArray(participants) &&
    participants.length > 0 &&
    Array.isArray(winners) &&
    winners.length > 0 &&
    Array.isArray(losers) &&
    losers.length > 0
  );
}

function knownGameTypeFromData(
  data: Record<string, unknown>
): KnownGameType | null {
  const gt = data.gameType;
  if (typeof gt !== "string") return null;
  return (KNOWN_GAME_TYPES as readonly string[]).includes(gt) ?
    (gt as KnownGameType) :
    null;
}

function emptyPerTypeMaps(): {
  gamesByType: Record<KnownGameType, number>;
  winsByType: Record<KnownGameType, number>;
} {
  const gamesByType = {} as Record<KnownGameType, number>;
  const winsByType = {} as Record<KnownGameType, number>;
  for (const t of KNOWN_GAME_TYPES) {
    gamesByType[t] = 0;
    winsByType[t] = 0;
  }
  return {gamesByType, winsByType};
}

function buildOddsAndGamesMaps(
  gamesByType: Record<KnownGameType, number>,
  winsByType: Record<KnownGameType, number>
): {
  oddsByGameType: Record<string, number>;
  gamesPlayedByGameType: Record<string, number>;
} {
  const oddsByGameType: Record<string, number> = {};
  const gamesPlayedByGameType: Record<string, number> = {};
  for (const t of KNOWN_GAME_TYPES) {
    const g = gamesByType[t];
    const w = winsByType[t];
    gamesPlayedByGameType[t] = g;
    oddsByGameType[t] = g === 0 ? 0 : w / g;
  }
  return {oddsByGameType, gamesPlayedByGameType};
}

interface OverallOddsResult {
  odds: number;
  games: number;
  overallOddsByGameType: Record<string, number>;
  overallGamesPlayedByGameType: Record<string, number>;
}

/**
 * Queries all eligible game logs for a profile and computes
 * overall odds, aggregate counts, and per–game-type odds/maps.
 * @param {string} profileId The profile to recompute.
 * @return {Promise<OverallOddsResult>} Computed values.
 */
async function computeOverallOdds(
  profileId: string
): Promise<OverallOddsResult> {
  const db = admin.firestore();
  const snap = await db
    .collection("gameLogs")
    .where("participantProfileIds", "array-contains", profileId)
    .get();

  let games = 0;
  let wins = 0;
  const {gamesByType, winsByType} = emptyPerTypeMaps();

  for (const doc of snap.docs) {
    const data = doc.data() as Record<string, unknown>;
    if (!isEligible(data)) continue;
    const log = data as unknown as EligibleLog;
    games++;
    const won = log.winnerProfileIds.includes(profileId);
    if (won) {
      wins++;
    }
    const gt = knownGameTypeFromData(data);
    if (gt) {
      gamesByType[gt]++;
      if (won) {
        winsByType[gt]++;
      }
    }
  }

  const odds = games === 0 ? 0 : wins / games;
  const {oddsByGameType, gamesPlayedByGameType} = buildOddsAndGamesMaps(
    gamesByType,
    winsByType
  );
  logger.debug("computeOverallOdds result", {
    profileId,
    games,
    wins,
    odds,
  });
  return {
    odds,
    games,
    overallOddsByGameType: oddsByGameType,
    overallGamesPlayedByGameType: gamesPlayedByGameType,
  };
}

interface CommunityOddsResult {
  odds: number;
  games: number;
  communityOddsByGameType: Record<string, number>;
  communityGamesPlayedByGameType: Record<string, number>;
}

/**
 * Queries eligible game logs scoped to one community for a
 * profile. Returns community odds, counts, and per–game-type maps.
 * @param {string} profileId The profile to recompute.
 * @param {string} communityId The community to scope to.
 * @return {Promise<CommunityOddsResult>} Computed values.
 */
async function computeCommunityOdds(
  profileId: string,
  communityId: string
): Promise<CommunityOddsResult> {
  const db = admin.firestore();
  const snap = await db
    .collection("gameLogs")
    .where(
      "participantProfileIds",
      "array-contains",
      profileId
    )
    .where("communityId", "==", communityId)
    .get();

  let games = 0;
  let wins = 0;
  const {gamesByType, winsByType} = emptyPerTypeMaps();

  for (const doc of snap.docs) {
    const data = doc.data() as Record<string, unknown>;
    if (!isEligible(data)) continue;
    const log = data as unknown as EligibleLog;
    games++;
    const won = log.winnerProfileIds.includes(profileId);
    if (won) {
      wins++;
    }
    const gt = knownGameTypeFromData(data);
    if (gt) {
      gamesByType[gt]++;
      if (won) {
        winsByType[gt]++;
      }
    }
  }

  const odds = games === 0 ? 0 : wins / games;
  const {oddsByGameType, gamesPlayedByGameType} = buildOddsAndGamesMaps(
    gamesByType,
    winsByType
  );
  logger.debug("computeCommunityOdds result", {
    profileId,
    communityId,
    games,
    wins,
    odds,
  });
  return {
    odds,
    games,
    communityOddsByGameType: oddsByGameType,
    communityGamesPlayedByGameType: gamesPlayedByGameType,
  };
}

/**
 * Writes community odds (aggregate + per game type) to
 * memberships/{communityId}_{profileId}.
 * Skips if the membership doc does not exist.
 * @param {string} profileId Target profile.
 * @param {string} communityId Target community.
 * @param {admin.firestore.FieldValue} now Server timestamp.
 * @param {string} gameLogId For log context only.
 * @return {Promise<void>}
 */
async function writeCommunityOdds(
  profileId: string,
  communityId: string,
  now: admin.firestore.FieldValue,
  gameLogId: string
): Promise<void> {
  const db = admin.firestore();
  const membershipId = `${communityId}_${profileId}`;
  const membershipRef = db
    .collection("memberships")
    .doc(membershipId);
  const membershipSnap = await membershipRef.get();

  if (!membershipSnap.exists) {
    logger.warn(
      "communityOdds recompute: membership not found, skipping",
      {profileId, communityId, membershipId, gameLogId}
    );
    return;
  }

  const {
    odds: communityOdds,
    games: communityGamesPlayed,
    communityOddsByGameType,
    communityGamesPlayedByGameType,
  } = await computeCommunityOdds(profileId, communityId);

  await membershipRef.update({
    communityOdds,
    communityGamesPlayed,
    communityOddsByGameType,
    communityGamesPlayedByGameType,
    updatedAt: now,
  });

  logger.info("communityOdds recompute: membership updated", {
    profileId,
    communityId,
    communityOdds,
    communityGamesPlayed,
  });
}

/**
 * Recomputes and persists overallOdds for all impacted profiles,
 * communityOdds and communityGamesPlayed for impacted
 * (profile, community) pairs, including per–game-type maps.
 * @param {OddsRecalcContext} ctx Event context including impacted
 * profile IDs and community info.
 * @return {Promise<void>}
 */
export async function recomputeOddsForGameLogEvent(
  ctx: OddsRecalcContext
): Promise<void> {
  const {
    gameLogId,
    kind,
    impactedProfileIds,
    communityId,
    previousCommunityId,
  } = ctx;

  logger.info("odds recompute started", {
    gameLogId,
    kind,
    impactedCount: impactedProfileIds.length,
    communityId,
    previousCommunityId,
  });

  if (impactedProfileIds.length === 0) {
    logger.warn("odds recompute: no impacted profiles", {
      gameLogId,
    });
    return;
  }

  const db = admin.firestore();
  const now = admin.firestore.FieldValue.serverTimestamp();

  await Promise.all(
    impactedProfileIds.map(async (profileId) => {
      const profileRef = db
        .collection("profiles")
        .doc(profileId);
      const profileSnap = await profileRef.get();

      if (!profileSnap.exists) {
        logger.warn(
          "odds recompute: profile not found, skipping",
          {profileId, gameLogId}
        );
        return;
      }

      const {
        odds: overallOdds,
        games: overallGamesPlayed,
        overallOddsByGameType,
        overallGamesPlayedByGameType,
      } = await computeOverallOdds(profileId);
      await profileRef.update({
        overallOdds,
        overallGamesPlayed,
        overallOddsByGameType,
        overallGamesPlayedByGameType,
        updatedAt: now,
      });
      logger.info("odds recompute: profile updated", {
        profileId,
        overallOdds,
        overallGamesPlayed,
      });

      if (communityId) {
        await writeCommunityOdds(
          profileId,
          communityId,
          now,
          gameLogId
        );
      }

      if (previousCommunityId) {
        await writeCommunityOdds(
          profileId,
          previousCommunityId,
          now,
          gameLogId
        );
      }
    })
  );

  logger.info("odds recompute complete", {
    gameLogId,
    kind,
    impactedCount: impactedProfileIds.length,
  });
}
