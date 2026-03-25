// bracketSeeding.ts calls admin.firestore() at module load; init default app first.
const admin = require("firebase-admin");
if (!admin.apps.length) {
  admin.initializeApp({projectId: "bcup-jest"});
}
