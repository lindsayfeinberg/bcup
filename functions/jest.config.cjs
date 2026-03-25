/** @type {import("jest").Config} */
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  watchman: false,
  setupFiles: ["<rootDir>/jest.setup.cjs"],
  roots: ["<rootDir>/src"],
  testMatch: ["**/*.test.ts"],
  moduleFileExtensions: ["ts", "js", "json"],
  // TypeScript sources use .js in import paths (NodeNext); map to extensionless for resolution.
  moduleNameMapper: {
    "^(\\.{1,2}/.*)\\.js$": "$1",
  },
  transform: {
    "^.+\\.ts$": [
      "ts-jest",
      {
        diagnostics: {ignoreCodes: [151002]},
      },
    ],
  },
};
