import * as admin from "firebase-admin";
import {onDocumentUpdated} from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";

const db = admin.firestore();
const region = "us-central1";

/**
 * Reads a string field from Firestore document data, or "".
 * @param {Record<string, unknown>|undefined} data Raw document data.
 * @param {string} key Field name.
 * @return {string} Trimmed string or empty.
 */
function stringField(
  data: Record<string, unknown> | undefined,
  key: string
): string {
  if (!data) return "";
  const v = data[key];
  return typeof v === "string" ? v : "";
}

/**
 * When a user changes display name or profile photo, fan out to every
 * `memberships/{communityId}_{uid}` row so league rosters and feed name
 * resolution stay in sync (membership docs are not client-writable).
 *
 * Skips work when only server-owned fields (e.g. odds) change on `profiles/*`.
 */
export const onProfileDisplayFieldsUpdated = onDocumentUpdated(
  {document: "profiles/{userId}", region},
  async (event) => {
    const userId = event.params.userId as string;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) {
      return;
    }

    const nameBefore = stringField(before, "displayName").trim();
    const nameAfter = stringField(after, "displayName").trim();
    const photoBefore = stringField(before, "profilePhotoUrl");
    const photoAfter = stringField(after, "profilePhotoUrl");

    if (nameBefore === nameAfter && photoBefore === photoAfter) {
      return;
    }

    const snap = await db
      .collection("memberships")
      .where("profileId", "==", userId)
      .get();

    if (snap.empty) {
      logger.info("onProfileDisplayFieldsUpdated: no memberships", {userId});
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const docs = snap.docs;
    const chunkSize = 450;

    for (let i = 0; i < docs.length; i += chunkSize) {
      const chunk = docs.slice(i, i + chunkSize);
      const batch = db.batch();
      for (const doc of chunk) {
        batch.update(doc.ref, {
          displayName: nameAfter,
          profilePhotoUrl: photoAfter || null,
          updatedAt: now,
        });
      }
      await batch.commit();
    }

    logger.info("onProfileDisplayFieldsUpdated: synced memberships", {
      userId,
      count: docs.length,
    });
  }
);
