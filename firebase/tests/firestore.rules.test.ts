import {readFileSync} from "fs";
import path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteField,
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
const ADMIN_UID = "platform_admin_uid";
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

  it("denies create when overallOddsByGameType is present", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(
        doc(db, "profiles", ALICE),
        profilePayload(ALICE, {
          overallOddsByGameType: {PONG: 0},
        })
      )
    );
  });

  it("allows profile update when server odds maps are unchanged", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adb = ctx.firestore();
      await setDoc(
        doc(adb, "profiles", ALICE),
        profilePayload(ALICE, {
          overallOdds: 0.6,
          overallGamesPlayed: 10,
          overallOddsByGameType: {PONG: 0.5},
          overallGamesPlayedByGameType: {PONG: 4},
        })
      );
    });
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(
      updateDoc(doc(db, "profiles", ALICE), {
        displayName: "Renamed",
        updatedAt: ts(),
      })
    );
  });

  it("denies profile update that mutates overallOddsByGameType", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const adb = ctx.firestore();
      await setDoc(
        doc(adb, "profiles", ALICE),
        profilePayload(ALICE, {
          overallOdds: 0.6,
          overallGamesPlayed: 10,
          overallOddsByGameType: {PONG: 0.5},
          overallGamesPlayedByGameType: {PONG: 4},
        })
      );
    });
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      updateDoc(doc(db, "profiles", ALICE), {
        overallOddsByGameType: {PONG: 0.99},
        updatedAt: ts(),
      })
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

function communityMessagePayload(
  messageId: string,
  authorUid: string,
  overrides: Record<string, unknown> = {}
) {
  const now = ts();
  return {
    id: messageId,
    communityId: COMM_ID,
    authorProfileId: authorUid,
    text: "Hello league",
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

describe("Firestore rules — community messages", () => {
  it("allows member to create with optional deleted false", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_001";
    const now = ts();
    await assertSucceeds(
      setDoc(doc(db, "communities", COMM_ID, "messages", mid), {
        id: mid,
        communityId: COMM_ID,
        authorProfileId: ALICE,
        text: "Hi",
        deleted: false,
        createdAt: now,
        updatedAt: now,
      })
    );
  });

  it("allows member to create without deleted key", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    const mid = "msg_002";
    await assertSucceeds(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, BOB)
      )
    );
  });

  it("allows another member to read a message", async () => {
    const dbA = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_read_1";
    await setDoc(
      doc(dbA, "communities", COMM_ID, "messages", mid),
      communityMessagePayload(mid, ALICE)
    );
    const dbB = testEnv.authenticatedContext(BOB).firestore();
    await assertSucceeds(
      getDoc(doc(dbB, "communities", COMM_ID, "messages", mid))
    );
  });

  it("denies create when not a community member", async () => {
    const db = testEnv.authenticatedContext(CHARLIE).firestore();
    const mid = "msg_no_member";
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, CHARLIE)
      )
    );
  });

  it("denies create when communityId does not match path", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_wrong_comm";
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, ALICE, {communityId: "other_community"})
      )
    );
  });

  it("denies create when authorProfileId is not caller", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_wrong_author";
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, ALICE, {authorProfileId: BOB})
      )
    );
  });

  it("denies create when text is empty", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_empty_text";
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, ALICE, {text: ""})
      )
    );
  });

  it("denies create when text exceeds 4000 chars", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_long";
    const longText = "a".repeat(4001);
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, ALICE, {text: longText})
      )
    );
  });

  it("denies create with unknown field", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_extra";
    await assertFails(
      setDoc(doc(db, "communities", COMM_ID, "messages", mid), {
        ...communityMessagePayload(mid, ALICE),
        extra: "nope",
      })
    );
  });

  it("denies create when deleted is true", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_deleted_true";
    await assertFails(
      setDoc(
        doc(db, "communities", COMM_ID, "messages", mid),
        communityMessagePayload(mid, ALICE, {deleted: true})
      )
    );
  });

  it("denies update and delete", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const mid = "msg_immutable";
    await setDoc(
      doc(db, "communities", COMM_ID, "messages", mid),
      communityMessagePayload(mid, ALICE)
    );
    await assertFails(
      updateDoc(doc(db, "communities", COMM_ID, "messages", mid), {
        text: "changed",
        updatedAt: ts(),
      })
    );
    await assertFails(
      deleteDoc(doc(db, "communities", COMM_ID, "messages", mid))
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
        gameType: "PONG",
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
        gameType: "PONG",
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
        gameType: "PONG",
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
      gameType: "PONG",
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

  it("allows member to create CUSTOM game log with customGameDefinitionId", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_custom_1";
    const now = ts();
    await assertSucceeds(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "CUSTOM",
        customGameDefinitionId: "gd_league_pong_plus",
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

  it("allows member to create CUSTOM game log with customGameDefinitionName", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_custom_named";
    const now = ts();
    await assertSucceeds(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "CUSTOM",
        customGameDefinitionId: "gd_league_pong_plus",
        customGameDefinitionName: "Pong Plus",
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

  it("denies CUSTOM game log with empty customGameDefinitionName", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_custom_empty_name";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "CUSTOM",
        customGameDefinitionId: "gd_league_pong_plus",
        customGameDefinitionName: "",
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

  it("denies built-in gameType with customGameDefinitionName set", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_builtin_name_bad";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "PONG",
        customGameDefinitionName: "Should not be here",
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

  it("denies CUSTOM game log without customGameDefinitionId", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_custom_bad";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "CUSTOM",
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

  it("denies built-in gameType with customGameDefinitionId set", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    const gameLogId = "log_builtin_custom_bad";
    const now = ts();
    await assertFails(
      setDoc(doc(db, "gameLogs", gameLogId), {
        id: gameLogId,
        communityId: COMM_ID,
        gameType: "PONG",
        customGameDefinitionId: "gd_should_not_be_here",
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

describe("Firestore rules — hidden leagues", () => {
  const hiddenLogId = "log_hidden_league";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      const now = ts();
      await updateDoc(doc(db, "communities", COMM_ID), {
        hiddenFromMembers: true,
        updatedAt: now,
      });
      await updateDoc(doc(db, "memberships", `${COMM_ID}_${BOB}`), {
        leagueHiddenForMember: true,
        updatedAt: now,
      });
      await setDoc(doc(db, "gameLogs", hiddenLogId), {
        id: hiddenLogId,
        communityId: COMM_ID,
        gameType: "PONG",
        createdByProfileId: ALICE,
        participantProfileIds: [ALICE, BOB],
        winnerProfileIds: [ALICE],
        loserProfileIds: [BOB],
        photoUrls: ["https://cdn.example/p.jpg"],
        notes: "",
        createdAt: now,
        updatedAt: now,
      });
      await setDoc(doc(db, "communities", COMM_ID, "messages", "msg_hidden_1"), {
        id: "msg_hidden_1",
        communityId: COMM_ID,
        authorProfileId: ALICE,
        text: "Thread while hidden",
        createdAt: now,
        updatedAt: now,
      });
    });
  });

  afterEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await deleteDoc(doc(db, "communities", COMM_ID, "messages", "msg_hidden_1"));
      await deleteDoc(doc(db, "gameLogs", hiddenLogId));
      await updateDoc(doc(db, "communities", COMM_ID), {
        hiddenFromMembers: false,
        updatedAt: ts(),
      });
      await updateDoc(doc(db, "memberships", `${COMM_ID}_${BOB}`), {
        leagueHiddenForMember: deleteField(),
        updatedAt: ts(),
      });
    });
  });

  it("denies non-creator member read on community when hidden", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertFails(getDoc(doc(db, "communities", COMM_ID)));
  });

  it("allows creator read on community when hidden", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(getDoc(doc(db, "communities", COMM_ID)));
  });

  it("denies non-creator member read on gameLogs when hidden", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertFails(getDoc(doc(db, "gameLogs", hiddenLogId)));
  });

  it("allows creator read on gameLogs when hidden", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(getDoc(doc(db, "gameLogs", hiddenLogId)));
  });

  it("denies non-creator member read on other memberships when hidden", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertFails(getDoc(doc(db, "memberships", `${COMM_ID}_${ALICE}`)));
  });

  it("allows non-creator member read on own membership when hidden", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertSucceeds(getDoc(doc(db, "memberships", `${COMM_ID}_${BOB}`)));
  });

  it("denies non-creator member read on messages when league hidden", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertFails(
      getDoc(doc(db, "communities", COMM_ID, "messages", "msg_hidden_1"))
    );
  });

  it("allows creator read on messages when league hidden", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertSucceeds(
      getDoc(doc(db, "communities", COMM_ID, "messages", "msg_hidden_1"))
    );
  });
});

describe("Firestore rules — adminActions", () => {
  const actionId = "admin_action_1";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "adminActions", actionId), {
        actorUid: ADMIN_UID,
        action: "deleteGameLog",
        targetGameLogId: "log_123",
        targetCommunityId: COMM_ID,
        createdAt: ts(),
      });
    });
  });

  it("allows platform admin read", async () => {
    const db = testEnv.authenticatedContext(
      ADMIN_UID,
      {platformAdmin: true}
    ).firestore();
    await assertSucceeds(getDoc(doc(db, "adminActions", actionId)));
  });

  it("denies non-admin read", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(getDoc(doc(db, "adminActions", actionId)));
  });

  it("denies client writes even for platform admin", async () => {
    const db = testEnv.authenticatedContext(
      ADMIN_UID,
      {platformAdmin: true}
    ).firestore();
    await assertFails(
      setDoc(doc(db, "adminActions", "new_action"), {
        actorUid: ADMIN_UID,
        action: "kickMember",
        createdAt: ts(),
      })
    );
    await assertFails(
      updateDoc(doc(db, "adminActions", actionId), {
        action: "tamper",
      })
    );
    await assertFails(deleteDoc(doc(db, "adminActions", actionId)));
  });
});

describe("Firestore rules — gameDefinitions", () => {
  const gameDefinitionId = "gd_pong_plus";

  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await setDoc(doc(db, "communities", COMM_ID, "gameDefinitions", gameDefinitionId), {
        id: gameDefinitionId,
        communityId: COMM_ID,
        name: "Pong Plus",
        rulesText: "11 cups, bounce shots count as 2.",
        createdByProfileId: ALICE,
        createdAt: ts(),
        updatedAt: ts(),
      });
    });
  });

  it("allows member read", async () => {
    const db = testEnv.authenticatedContext(BOB).firestore();
    await assertSucceeds(
      getDoc(doc(db, "communities", COMM_ID, "gameDefinitions", gameDefinitionId))
    );
  });

  it("denies non-member read", async () => {
    const db = testEnv.authenticatedContext(CHARLIE).firestore();
    await assertFails(
      getDoc(doc(db, "communities", COMM_ID, "gameDefinitions", gameDefinitionId))
    );
  });

  it("denies client writes", async () => {
    const db = testEnv.authenticatedContext(ALICE).firestore();
    await assertFails(
      setDoc(doc(db, "communities", COMM_ID, "gameDefinitions", "gd_new"), {
        id: "gd_new",
        communityId: COMM_ID,
        name: "New custom game",
        rulesText: null,
        createdByProfileId: ALICE,
        createdAt: ts(),
        updatedAt: ts(),
      })
    );
    await assertFails(
      updateDoc(doc(db, "communities", COMM_ID, "gameDefinitions", gameDefinitionId), {
        name: "Tamper",
      })
    );
    await assertFails(
      deleteDoc(doc(db, "communities", COMM_ID, "gameDefinitions", gameDefinitionId))
    );
  });
});
