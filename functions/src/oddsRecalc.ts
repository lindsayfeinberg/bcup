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

/**
 * Queries all eligible game logs for a profile and computes
 * overallOdds = wins / games (0 if no games).
 * @param {string} profileId The profile to recompute.
 * @return {Promise<number>} Computed overallOdds value.
 */
interface OverallOddsResult {
    odds: number;
    games: number;
}
/**
 * Queries all eligible game logs for a profile and computes
 * overallOdds and overallGamesPlayed.
 * @param {string} profileId The profile to recompute.
 * @return {Promise<OverallOddsResult>} Computed odds and game count.
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

  for (const doc of snap.docs) {
    const data = doc.data() as Record<string, unknown>;
    if (!isEligible(data)) continue;
    const log = data as unknown as EligibleLog;
    games++;
    if (log.winnerProfileIds.includes(profileId)) {
      wins++;
    }
  }

  const odds = games === 0 ? 0 : wins / games;
  logger.debug("computeOverallOdds result", {
    profileId,
    games,
    wins,
    odds,
  });
  return {odds, games};
}

interface CommunityOddsResult {
  odds: number;
  games: number;
}

/**
 * Queries eligible game logs scoped to one community for a
 * profile. Returns both communityOdds and communityGamesPlayed
 * so the caller can persist both in a single pass.
 * Requires composite index: participantProfileIds array-contains
 * + communityId == (see firestore.indexes.json).
 * @param {string} profileId The profile to recompute.
 * @param {string} communityId The community to scope to.
 * @return {Promise<CommunityOddsResult>} Odds and game count.
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

  for (const doc of snap.docs) {
    const data = doc.data() as Record<string, unknown>;
    if (!isEligible(data)) continue;
    const log = data as unknown as EligibleLog;
    games++;
    if (log.winnerProfileIds.includes(profileId)) {
      wins++;
    }
  }

  const odds = games === 0 ? 0 : wins / games;
  logger.debug("computeCommunityOdds result", {
    profileId,
    communityId,
    games,
    wins,
    odds,
  });
  return {odds, games};
}

/**
 * Writes communityOdds and communityGamesPlayed to
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

  const {odds: communityOdds, games: communityGamesPlayed} =
    await computeCommunityOdds(profileId, communityId);

  await membershipRef.update({
    communityOdds,
    communityGamesPlayed,
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
 * (profile, community) pairs.
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

      // T09.2: overall odds
      const {
        odds: overallOdds,
        games: overallGamesPlayed,
      } = await computeOverallOdds(profileId);
      await profileRef.update({
        overallOdds,
        overallGamesPlayed,
        updatedAt: now,
      });
      logger.info("odds recompute: profile updated", {
        profileId,
        overallOdds,
        overallGamesPlayed,
      });

      // T09.3/T09.4: community odds + gamesPlayed for current
      if (communityId) {
        await writeCommunityOdds(
          profileId,
          communityId,
          now,
          gameLogId
        );
      }

      // T09.3/T09.4: community odds + gamesPlayed for previous
      // (only on update when communityId changed)
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
