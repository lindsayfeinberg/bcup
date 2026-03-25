import * as logger from "firebase-functions/logger";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentDeleted,
} from "firebase-functions/v2/firestore";
import {
  recomputeOddsForGameLogEvent,
  GameLogEventKind,
  OddsRecalcContext,
} from "./oddsRecalc.js";
import {applyBracketOutcomeFromGameLogCreate} from "./bracketGameLogSync.js";

const DOCUMENT_PATH = "gameLogs/{gameLogId}";
const region = "us-central1";

/**
 * Dedupes and unions two participant arrays into a
 * single impacted profile ID list.
 * @param {string[]} a First participant array.
 * @param {string[]} b Second participant array.
 * @return {string[]} Deduped union.
 */
function unionIds(a: string[], b: string[]): string[] {
  return [...new Set([...a, ...b])];
}

/**
 * Shared handler for all gameLog Firestore trigger events.
 * @param {string} gameLogId The Firestore document ID.
 * @param {GameLogEventKind} kind The event type.
 * @param {Record<string, unknown> | null} afterData Post-event data.
 * @param {Record<string, unknown> | null} beforeData Pre-event data.
 * @return {Promise<void>}
 */
async function handleGameLogChange(
  gameLogId: string,
  kind: GameLogEventKind,
  afterData: Record<string, unknown> | null,
  beforeData: Record<string, unknown> | null
): Promise<void> {
  const communityId =
    (afterData?.communityId as string | undefined) ??
    (beforeData?.communityId as string | undefined) ??
    null;

  const afterCommunityId =
    afterData?.communityId as string | undefined;
  const beforeCommunityId =
    beforeData?.communityId as string | undefined;
  const previousCommunityId =
    beforeCommunityId !== afterCommunityId ?
      (beforeCommunityId ?? null) :
      null;

  const afterParticipants =
    (
      afterData?.participantProfileIds as string[] | undefined
    ) ?? [];
  const beforeParticipants =
    (
      beforeData?.participantProfileIds as string[] | undefined
    ) ?? [];

  // create → after only
  // update → union(before, after) in case participant list changed
  // delete → before only
  const impactedProfileIds = unionIds(
    afterParticipants,
    beforeParticipants
  );

  logger.info(`gameLog.${kind}`, {
    gameLogId,
    communityId,
    previousCommunityId: previousCommunityId ?? "(unchanged)",
    kind,
    impactedCount: impactedProfileIds.length,
  });

  if (kind === "updated" && previousCommunityId) {
    logger.info("gameLog.communityId changed", {
      gameLogId,
      from: previousCommunityId,
      to: communityId,
    });
  }

  const ctx: OddsRecalcContext = {
    gameLogId,
    communityId,
    previousCommunityId,
    impactedProfileIds,
    kind,
  };

  if (kind === "created" && afterData) {
    await applyBracketOutcomeFromGameLogCreate(gameLogId, afterData);
  }

  await recomputeOddsForGameLogEvent(ctx);
}

export const onGameLogCreated = onDocumentCreated(
  {document: DOCUMENT_PATH, region},
  async (event) => {
    const gameLogId = event.params.gameLogId;
    const afterData = (
      event.data?.data() ?? null
    ) as Record<string, unknown> | null;
    logger.info("onGameLogCreated fired", {gameLogId});
    await handleGameLogChange(
      gameLogId, "created", afterData, null
    );
  }
);

export const onGameLogUpdated = onDocumentUpdated(
  {document: DOCUMENT_PATH, region},
  async (event) => {
    const gameLogId = event.params.gameLogId;
    const afterData = (
      event.data?.after.data() ?? null
    ) as Record<string, unknown> | null;
    const beforeData = (
      event.data?.before.data() ?? null
    ) as Record<string, unknown> | null;
    logger.info("onGameLogUpdated fired", {gameLogId});
    await handleGameLogChange(
      gameLogId, "updated", afterData, beforeData
    );
  }
);

export const onGameLogDeleted = onDocumentDeleted(
  {document: DOCUMENT_PATH, region},
  async (event) => {
    const gameLogId = event.params.gameLogId;
    const beforeData = (
      event.data?.data() ?? null
    ) as Record<string, unknown> | null;
    logger.info("onGameLogDeleted fired", {gameLogId});
    await handleGameLogChange(
      gameLogId, "deleted", null, beforeData
    );
  }
);
