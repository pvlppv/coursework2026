import { describe, expect, it } from "vitest";
import { loadEnv } from "../src/config/env.js";

describe("loadEnv", () => {
  it("loads the minimal required backend environment", () => {
    const env = loadEnv({
      SESSION_JWT_SECRET: "a".repeat(32),
      OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
    });

    expect(env.PORT).toBe(8080);
    expect(env.APPLE_ENVIRONMENT).toBe("Sandbox");
    expect(env.ENABLE_TEST_INSTALL_ALLOWLIST).toBe(false);
    expect(env.PREMIUM_DAILY_RESPONSE_LIMIT).toBe(200);
  });

  it("parses the test install allowlist flag", () => {
    const env = loadEnv({
      SESSION_JWT_SECRET: "a".repeat(32),
      OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
      ENABLE_TEST_INSTALL_ALLOWLIST: "true",
    });

    expect(env.ENABLE_TEST_INSTALL_ALLOWLIST).toBe(true);
  });

  it("requires appAppleId for production StoreKit verification", () => {
    expect(() =>
      loadEnv({
        SESSION_JWT_SECRET: "a".repeat(32),
        OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
        APPLE_ENVIRONMENT: "Production",
      }),
    ).toThrow(/APPLE_APP_APPLE_ID/);
  });
});
