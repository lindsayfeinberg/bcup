/** @type {import("jest").Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  watchman: false,
  testTimeout: 120000,
  roots: ["<rootDir>"],
  testMatch: ["**/*.rules.test.ts"],
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      {diagnostics: {ignoreCodes: [151002]}},
    ],
  },
};
