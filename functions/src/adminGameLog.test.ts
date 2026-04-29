import {isPlatformAdminToken} from "./adminGameLog.js";

describe("isPlatformAdminToken", () => {
  it("is false when token is undefined", () => {
    expect(isPlatformAdminToken(undefined)).toBe(false);
  });

  it("is false when claim is absent or not true", () => {
    expect(isPlatformAdminToken({})).toBe(false);
    expect(isPlatformAdminToken({platformAdmin: false})).toBe(false);
    expect(isPlatformAdminToken({platformAdmin: "yes"})).toBe(false);
  });

  it("is true when platformAdmin is true", () => {
    expect(isPlatformAdminToken({platformAdmin: true})).toBe(true);
  });
});
