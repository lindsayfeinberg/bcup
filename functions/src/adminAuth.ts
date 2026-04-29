import {
  HttpsError,
  type CallableRequest,
} from "firebase-functions/v2/https";

/**
 * Callable API envelope per api-contracts.
 * @param {T} data Payload for the client.
 * @return {object} Wrapped response with meta.requestId.
 * @template T
 */
export function newEnvelope<T extends Record<string, unknown>>(data: T) {
  const suffix = Math.random().toString(36).slice(2, 9);
  return {
    ok: true,
    apiVersion: "v1",
    data,
    meta: {requestId: `req_${Date.now()}_${suffix}`},
  };
}

/**
 * True when the ID token carries the platform operator claim.
 * @param {Record<string, unknown> | undefined} token Decoded ID token fields.
 * @return {boolean}
 */
export function isPlatformAdminToken(
  token: Record<string, unknown> | undefined
): boolean {
  return token?.platformAdmin === true;
}

/**
 * Requires Firebase Auth custom claim `platformAdmin: true`.
 * @param {CallableRequest["auth"]} auth Callable auth context.
 */
export function assertPlatformAdmin(auth: CallableRequest["auth"]): void {
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in required");
  }
  const token = auth.token as Record<string, unknown>;
  if (!isPlatformAdminToken(token)) {
    throw new HttpsError("permission-denied", "Platform admin only");
  }
}
