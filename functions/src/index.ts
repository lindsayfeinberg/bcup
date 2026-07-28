import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {
  createCommunity,
  createGameDefinition,
  deleteGameDefinition,
  joinCommunity,
  listGameDefinitions,
  previewJoinCommunity,
  setCommunityHidden,
  updateGameDefinition,
} from "./communities.js";

export {
  createCommunity,
  createGameDefinition,
  deleteGameDefinition,
  joinCommunity,
  listGameDefinitions,
  previewJoinCommunity,
  setCommunityHidden,
  updateGameDefinition,
};

export const healthcheck = onRequest((request, response) => {
  logger.info("Functions healthcheck hit", {method: request.method});
  response.status(200).send("bcup functions ready");
});
export {
  onGameLogCreated,
  onGameLogUpdated,
  onGameLogDeleted,
} from "./gameLogTriggers.js";
export {createBracket, createLeagueBracket} from "./brackets.js";
export {finalizeManualBracket} from "./bracketManualSeed.js";
export {updateMatchResult} from "./bracketGameLogSync.js";
export {adminDeleteGameLog, adminUpdateGameLog} from "./adminGameLog.js";
export {
  adminDeleteLeagueMessage,
  adminKickMember,
  adminListActions,
  adminListCommunities,
  adminListGameLogs,
} from "./platformAdmin.js";
export {onProfileDisplayFieldsUpdated} from "./profileMembershipSync.js";
export {
  startLiveStream,
  endLiveStream,
  joinLiveStreamAsViewer,
  leaveLiveStreamAsViewer,
} from "./liveStreams.js";
