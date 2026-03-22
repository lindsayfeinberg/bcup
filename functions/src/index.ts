import {onRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import {createCommunity, joinCommunity} from "./communities.js";

export {createCommunity, joinCommunity};

export const healthcheck = onRequest((request, response) => {
  logger.info("Functions healthcheck hit", {method: request.method});
  response.status(200).send("bcup functions ready");
});
