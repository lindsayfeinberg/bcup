import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {
  createCommunity,
  joinCommunity,
  previewJoinCommunity,
} from "./communities.js";

export {createCommunity, joinCommunity, previewJoinCommunity};

export const healthcheck = onRequest((request, response) => {
  logger.info("Functions healthcheck hit", {method: request.method});
  response.status(200).send("bcup functions ready");
});
export {
  onGameLogCreated,
  onGameLogUpdated,
  onGameLogDeleted,
} from "./gameLogTriggers.js";
export {createBracket} from "./brackets.js";
export {finalizeManualBracket} from "./bracketManualSeed.js";
