import * as admin from "firebase-admin";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import {AccessToken, RoomServiceClient} from "livekit-server-sdk";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const region = "us-central1";

const livekitUrl = defineSecret("LIVEKIT_URL");
const livekitApiKey = defineSecret("LIVEKIT_API_KEY");
const livekitApiSecret = defineSecret("LIVEKIT_API_SECRET");

const liveStreamSecrets = [livekitUrl, livekitApiKey, livekitApiSecret];

/**
 * Callable API envelope per api-contracts (mirrors `communities.ts`).
 * @param {T} data Payload for the client.
 * @return {object} Wrapped response with meta.requestId.
 * @template T
 */
function newEnvelope<T extends Record<string, unknown>>(data: T) {
  const suffix = Math.random().toString(36).slice(2, 9);
  return {
    ok: true,
    apiVersion: "v1",
    data,
    meta: {requestId: `req_${Date.now()}_${suffix}`},
  };
}

/**
 * Builds a LiveKit `RoomServiceClient` from the configured secrets.
 * @return {RoomServiceClient} Server-side client for room lifecycle calls.
 */
function roomServiceClient(): RoomServiceClient {
  return new RoomServiceClient(
    livekitUrl.value(),
    livekitApiKey.value(),
    livekitApiSecret.value()
  );
}

/**
 * Throws PERMISSION_DENIED unless the user has a `memberships` row for the
 * league.
 * @param {string} uid Signed-in user id.
 * @param {string} communityId League id.
 * @return {Promise<void>} Resolves when membership is confirmed.
 */
async function requireCommunityMembership(
  uid: string,
  communityId: string
): Promise<void> {
  const membershipId = `${communityId}_${uid}`;
  const snap = await db.collection("memberships").doc(membershipId).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "Not a member of this league");
  }
}

export const startLiveStream = onCall(
  {region, secrets: liveStreamSecrets},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const communityId = typeof request.data?.communityId === "string" ?
      request.data.communityId.trim() :
      "";
    if (!communityId) {
      throw new HttpsError("invalid-argument", "communityId is required");
    }

    await requireCommunityMembership(uid, communityId);

    const existing = await db.collection("liveStreams")
      .where("hostUserId", "==", uid)
      .where("status", "==", "live")
      .limit(1)
      .get();
    if (!existing.empty) {
      throw new HttpsError(
        "already-exists",
        "You already have a live stream in progress"
      );
    }

    const profileSnap = await db.collection("profiles").doc(uid).get();
    const hostDisplayName =
      (profileSnap.data()?.displayName as string | undefined) ?? "";

    const streamRef = db.collection("liveStreams").doc();
    const streamId = streamRef.id;
    const roomName = streamId;
    const now = admin.firestore.FieldValue.serverTimestamp();

    try {
      await roomServiceClient().createRoom({
        name: roomName,
        emptyTimeout: 300,
        maxParticipants: 200,
      });
    } catch (e) {
      logger.error("startLiveStream: createRoom failed", e);
      throw new HttpsError("internal", "Could not start the stream");
    }

    await streamRef.set({
      id: streamId,
      communityId,
      hostUserId: uid,
      hostDisplayName,
      roomName,
      status: "live",
      viewerCount: 0,
      startedAt: now,
      endedAt: null,
      createdAt: now,
      updatedAt: now,
    });

    const token = new AccessToken(
      livekitApiKey.value(),
      livekitApiSecret.value(),
      {identity: uid, name: hostDisplayName}
    );
    token.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
    });
    const jwt = await token.toJwt();

    return newEnvelope({
      streamId,
      roomName,
      livekitUrl: livekitUrl.value(),
      token: jwt,
    });
  }
);

export const endLiveStream = onCall(
  {region, secrets: liveStreamSecrets},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const streamId = typeof request.data?.streamId === "string" ?
      request.data.streamId.trim() :
      "";
    if (!streamId) {
      throw new HttpsError("invalid-argument", "streamId is required");
    }

    const streamRef = db.collection("liveStreams").doc(streamId);
    const snap = await streamRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Stream not found");
    }
    const data = snap.data();
    if (!data || data.hostUserId !== uid) {
      throw new HttpsError(
        "permission-denied",
        "Only the host can end this stream"
      );
    }

    if (data.status === "live") {
      try {
        await roomServiceClient().deleteRoom(data.roomName as string);
      } catch (e) {
        // Room may already be gone (e.g. empty-room timeout) — not fatal.
        logger.warn("endLiveStream: deleteRoom failed", e);
      }
      await streamRef.update({
        status: "ended",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    return newEnvelope({streamId});
  }
);

export const joinLiveStreamAsViewer = onCall(
  {region, secrets: liveStreamSecrets},
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;
    const streamId = typeof request.data?.streamId === "string" ?
      request.data.streamId.trim() :
      "";
    if (!streamId) {
      throw new HttpsError("invalid-argument", "streamId is required");
    }

    const streamRef = db.collection("liveStreams").doc(streamId);
    const snap = await streamRef.get();
    if (!snap.exists) {
      throw new HttpsError("not-found", "Stream not found");
    }
    const data = snap.data();
    if (!data) {
      throw new HttpsError("not-found", "Stream not found");
    }
    if (data.status !== "live") {
      throw new HttpsError("failed-precondition", "This stream has ended");
    }

    await requireCommunityMembership(uid, data.communityId as string);

    const profileSnap = await db.collection("profiles").doc(uid).get();
    const displayName =
      (profileSnap.data()?.displayName as string | undefined) ?? "";

    const token = new AccessToken(
      livekitApiKey.value(),
      livekitApiSecret.value(),
      {identity: uid, name: displayName}
    );
    token.addGrant({
      roomJoin: true,
      room: data.roomName as string,
      canPublish: false,
      canSubscribe: true,
    });
    const jwt = await token.toJwt();

    await streamRef.update({
      viewerCount: admin.firestore.FieldValue.increment(1),
    });

    return newEnvelope({
      streamId,
      roomName: data.roomName,
      livekitUrl: livekitUrl.value(),
      token: jwt,
    });
  }
);

export const leaveLiveStreamAsViewer = onCall({region}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const streamId = typeof request.data?.streamId === "string" ?
    request.data.streamId.trim() :
    "";
  if (!streamId) {
    throw new HttpsError("invalid-argument", "streamId is required");
  }

  const streamRef = db.collection("liveStreams").doc(streamId);
  const snap = await streamRef.get();
  if (snap.exists) {
    await streamRef.update({
      viewerCount: admin.firestore.FieldValue.increment(-1),
    });
  }

  return newEnvelope({streamId});
});
