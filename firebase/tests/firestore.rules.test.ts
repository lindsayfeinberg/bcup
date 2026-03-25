import {readFileSync} from "fs";
import path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  doc,
  getDoc,
  setDoc,
  deleteDoc,
  updateDoc,
  Timestamp,
} from "firebase/firestore";

const RULES_PATH = path.join(__dirname, "..", "firestore.rules");

const ALICE = "alice_uid";
const BOB = "bob_uid";
const CHARLIE = "charlie_uid";
const COMM_ID = "community_test_1";

let testEnv: RulesTestEnvironment;

function ts() {
  return Timestamp.now();
}

async function seedFirestore(testEnvInstance: RulesTestEnvironment) {
  await testEnvInstance.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    const now = ts();
    await setDoc(doc(db, "communities", COMM_ID), {
      id: COMM_ID,
      name: "Test League",
      createdByProfileId: ALICE,
      inviteCode: "JOIN01",
      inviteLink: "https://example.invalid/join/JOIN01",
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

function profilePayload(profileId: string, overrides: Record<string, unknown> = {}) {
  const now = ts();
  return {
    id: profileId,
    googleAuthId: profileId,
    displayName: "Player",
    profilePhotoUrl: null,
    overallOdds: 0,
    overallGamesPlayed: 0,
    ageConfirmed21PlusAt: now,
    onboardingCompleteAt: now,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-bc-rules",
    firestore: {
      rules: readFileSync(RULES_PATH, "utf8"),
    },
  });
  await seedFirestore(testEnv);
});

afterAll(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await seedFirestore(testEnv);
});

describe("Firestore rules — profiles", () => {
  it("denies unauthenticated read", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "profiles", ALICE)));
  });

  it("allows user to read own profile doc", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(getDoc(doc(db, "profiles", ALICE)));
  });

  it("denies reading another user's profile", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertFails(getDoc(doc(db, "profiles", ALICE)));
  });

  it("allows create of own profile with valid fields", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(
      setDoc(doc(db, "profiles", ALICE), profilePayload(ALICE))
    );
  });

  it("denies create when overallOdds is not 0", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(
        doc(db, "profiles", ALICE),
        profilePayload(ALICE, {overallOdds: 0.5})
      )
    );
  });

  it("denies delete", async () => {
    const ctx = testEnv.authenticatedContext(ALICE);
    const db = ctx.firestore();
    await setDoc(doc(db, "profiles", ALICE), profilePayload(ALICE));
    await assertFails(deleteDoc(doc(db, "profiles", ALICE)));
  });
});

describe("Firestore rules — communities", () => {
  it("denies unauthenticated read", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, "communities", COMM_ID)));
  });

  it("denies read when not a member", async () => {
    const db = testEnv.authenticatedContext(CHARLIE).firestore();
    await assertFails(getDoc(doc(db, "communities", COMM_ID)));
  });

  it("allows read for community member", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(getDoc(doc(db, "communities", COMM_ID)));
  });

  it("denies client create", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const now = ts();
    await assertFails(
      setDoc(doc(db, "communities", "new_comm"), {
        id: "new_comm",
        name: "Nope",
        createdByProfileId: ALICE,
        inviteCode: "X",
        inviteLink: "https://x",
        createdAt: now,
        updatedAt: now,
      })
    );
  });

  it("allows creator to update name while preserving invariants", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const snap = await getDoc(doc(db, "communities", COMM_ID));
    const data = snap.data()!;
    await assertSucceeds(
      updateDoc(doc(db, "communities", COMM_ID), {
        name: "Renamed League",
        updatedAt: ts(),
        id: data.id,
        createdByProfileId: data.createdByProfileId,
        inviteCode: data.inviteCode,
        inviteLink: data.inviteLink,
        createdAt: data.createdAt,
      })
    );
  });
});

describe("Firestore rules — memberships", () => {
  it("denies client create", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(doc(db, "memberships", "fake"), {
        profileId: ALICE,
        communityId: COMM_ID,
      })
    );
  });

  it("denies update", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      updateDoc(doc(db, "memberships", `${COMM_ID}_${ALICE}`), {
        profileId: ALICE,
      })
    );
  });
});

describe("Firestore rules — gameLogs", () => {
  it("allows member to create a valid game log", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_001";
    const now = ts();
    await assertSucceeds(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "pong",
        createdByProfileId: ALICE,
        participantProfileIds: [ALICE, BOB],
        winnerProfileIds: [ALICE],
        loserProfileIds: [BOB],
        photoUrls: ["https://cdn.example/photo.jpg"],
        notes: "",
        createdAt: now,
        updatedAt: now,
      })
    );
  });

  it("denies create when user is not a community member", async () => {
    const db = testEnv.authenticatedContext(CHARLIE).firestore();
    const gameLogId = "log_002";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "pong",
        createdByProfileId: CHARLIE,
        participantProfileIds: [CHARLIE, "other"],
        winnerProfileIds: [CHARLIE],
        loserProfileIds: ["other"],
        photoUrls: ["https://cdn.example/p.jpg"],
        notes: "",
        createdAt: now,
        updatedAt: now,
      })
    );
  });

  it("denies create when photoUrls count is not 1", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_003";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "pong",
        createdByProfileId: ALICE,
        participantProfileIds: [ALICE, BOB],
        winnerProfileIds: [ALICE],
        loserProfileIds: [BOB],
        photoUrls: [],
        notes: "",
        createdAt: now,
        updatedAt: now,
      })
    );
  });

  it("allows creator to delete", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_del";
    const now = ts();
    await setDoc(doc(db, "gameLogs", gameLogId), {
      id: gameLogId,
      communityId: COMM_ID,
      gameType: "pong",
      createdByProfileId: ALICE,
      participantProfileIds: [ALICE, BOB],
      winnerProfileIds: [ALICE],
      loserProfileIds: [BOB],
      photoUrls: ["https://cdn.example/p.jpg"],
      notes: "",
      createdAt: now,
      updatedAt: now,
    });
    await assertSucceeds(deleteDoc(doc(db, "gameLogs", gameLogId)));
  });
});

describe("Firestore rules — brackets", () => {
  it("allows member to read bracket", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const bracketId = "bracket_1";
      const now = ts();
      await setDoc(doc(db, "brackets", bracketId), {
        id: bracketId,
        communityId: COMM_ID,
        participantProfileIds: [ALICE, BOB],
        seedMethod: "COMMUNITY_ODDS",
        teamSize: 1,
        status: "ACTIVE",
        rounds: [],
        createdAt: now,
        updatedAt: now,
      });
    });
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertSucceeds(getDoc(doc(db, "brackets", "bracket_1")));
  });

  it("denies read when not a member", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const bracketId = "bracket_2";
      const now = ts();
      await setDoc(doc(db, "brackets", bracketId), {
        id: bracketId,
        communityId: COMM_ID,
        participantProfileIds: [ALICE, BOB],
        seedMethod: "RANDOM",
        teamSize: 1,
        status: "ACTIVE",
        rounds: [],
        createdAt: now,
        updatedAt: now,
      });
    });
    const db = testEnv.authenticatedContext(CHARLIE).firestore();
    await assertFails(getDoc(doc(db, "brackets", "bracket_2")));
  });

  it("allows member to create bracket with valid keys", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const bracketId = "bracket_new";
    const now = ts();
    await assertSucceeds(
      setDoc(doc(db, "brackets", bracketId), {
        id: bracketId,
        communityId: COMM_ID,
        participantProfileIds: [ALICE, BOB],
        seedMethod: "MANUAL",
        teamSize: 1,
        status: "DRAFT",
        rounds: [],
        createdAt: now,
        updatedAt: now,
      })
    );
  });
});
