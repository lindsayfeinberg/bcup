import {readFileSync} from "fs";
import path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {doc, setDoc, Timestamp} from "firebase/firestore";
import {ref, uploadBytes, getBytes, deleteObject} from "firebase/storage";

const FIRESTORE_RULES = path.join(__dirname, "..", "firestore.rules");
const STORAGE_RULES = path.join(__dirname, "..", "storage.rules");

const ALICE = "alice_uid";
const BOB = "bob_uid";
const CHARLIE = "charlie_uid";
const COMM_ID = "community_storage_1";

/** Minimal valid PNG (1x1). */
const PNG_1X1 = new Uint8Array(
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
    "base64"
  )
);

let testEnv: RulesTestEnvironment;

function ts() {
  return Timestamp.now();
}

async function seedMembership(testEnvInstance: RulesTestEnvironment) {
  await testEnvInstance.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const now = ts();
    await setDoc(doc(db, "communities", COMM_ID), {
      id: COMM_ID,
      name: "Storage League",
      createdByProfileId: ALICE,
      inviteCode: "STOR01",
      inviteLink: "https://example.invalid/s",
      createdAt: now,
      updatedAt: now,
    });
    for (const uid of [ALICE, BOB]) {
      await setDoc(doc(db, "memberships", `${COMM_ID}_${uid}`), {
        profileId: uid,
        communityId: COMM_ID,
      });
    }
  });
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-bc-rules",
    firestore: {
      rules: readFileSync(FIRESTORE_RULES, "utf8"),
    },
    storage: {
      rules: readFileSync(STORAGE_RULES, "utf8"),
    },
  });
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seedMembership(testEnv);
});

describe("Storage rules — profilePhotos", () => {
  it("denies read when not signed in", async () => {
    const storage = testEnv.unauthenticatedContext().storage();
    const r = ref(storage, `profilePhotos/${ALICE}/x.png`);
    await assertFails(getBytes(r));
  });

  it("allows any signed-in user to read profile photos", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminStorage = ctx.storage();
      await uploadBytes(
        ref(adminStorage, `profilePhotos/${ALICE}/seed.png`),
        PNG_1X1,
        {contentType: "image/png"}
      );
    });
    const storage = testEnv.authenticatedContext(BOB).storage();
    await assertSucceeds(
      getBytes(ref(storage, `profilePhotos/${ALICE}/seed.png`))
    );
  });

  it("allows owner to upload image", async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();
    const r = ref(storage, `profilePhotos/${ALICE}/me.png`);
    await assertSucceeds(
      uploadBytes(r, PNG_1X1, {contentType: "image/png"})
    );
  });

  it("denies upload to another user's folder", async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();
    const r = ref(storage, `profilePhotos/${BOB}/hack.png`);
    await assertFails(
      uploadBytes(r, PNG_1X1, {contentType: "image/png"})
    );
  });
});

describe("Storage rules — gamePhotos", () => {
  it("denies read when not a community member", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminStorage = ctx.storage();
      await uploadBytes(
        ref(adminStorage, `gamePhotos/${COMM_ID}/log_x/p.png`),
        PNG_1X1,
        {contentType: "image/png"}
      );
    });
    const storage = testEnv.authenticatedContext(CHARLIE).storage();
    await assertFails(
      getBytes(ref(storage, `gamePhotos/${COMM_ID}/log_x/p.png`))
    );
  });

  it("allows member to read game photos", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adminStorage = ctx.storage();
      await uploadBytes(
        ref(adminStorage, `gamePhotos/${COMM_ID}/log_y/p.png`),
        PNG_1X1,
        {contentType: "image/png"}
      );
    });
    const storage = testEnv.authenticatedContext(BOB).storage();
    await assertSucceeds(
      getBytes(ref(storage, `gamePhotos/${COMM_ID}/log_y/p.png`))
    );
  });

  it("allows member to upload with createdByProfileId metadata", async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();
    const r = ref(storage, `gamePhotos/${COMM_ID}/log_z/up.png`);
    await assertSucceeds(
      uploadBytes(r, PNG_1X1, {
        contentType: "image/png",
        customMetadata: {createdByProfileId: ALICE},
      })
    );
  });

  it("denies upload when metadata uid does not match caller", async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();
    const r = ref(storage, `gamePhotos/${COMM_ID}/log_bad/bad.png`);
    await assertFails(
      uploadBytes(r, PNG_1X1, {
        contentType: "image/png",
        customMetadata: {createdByProfileId: BOB},
      })
    );
  });

  it("allows uploader to delete own game photo", async () => {
    const storage = testEnv.authenticatedContext(ALICE).storage();
    const r = ref(storage, `gamePhotos/${COMM_ID}/log_del/del.png`);
    await uploadBytes(r, PNG_1X1, {
      contentType: "image/png",
      customMetadata: {createdByProfileId: ALICE},
    });
    await assertSucceeds(deleteObject(r));
  });
});
