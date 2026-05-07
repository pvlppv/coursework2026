import { describe, expect, it, vi } from "vitest";
import { loadEnv } from "../src/config/env.js";
import { SessionStore } from "../src/services/session-store.js";

function redisMock(values: Map<string, string> = new Map()) {
  return {
    get: vi.fn(async (key: string) => values.get(key) ?? null),
    set: vi.fn(async (key: string, value: string) => {
      values.set(key, value);
      return "OK";
    }),
    sadd: vi.fn(async () => 1),
    expire: vi.fn(async () => 1),
    del: vi.fn(async (key: string) => (values.delete(key) ? 1 : 0)),
  };
}

describe("SessionStore test install allowlist", () => {
  it("returns free when the allowlist is disabled", async () => {
    const values = new Map([
      ["test-install:install-allowlisted-1:entitlement", JSON.stringify({ state: "premium", verifiedAt: new Date().toISOString() })],
    ]);
    const store = new SessionStore(
      redisMock(values) as never,
      loadEnv({
        NODE_ENV: "test",
        SESSION_JWT_SECRET: "a".repeat(32),
        OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
        ENABLE_TEST_INSTALL_ALLOWLIST: "false",
      }),
    );

    await expect(store.getEntitlement("install-allowlisted-1")).resolves.toEqual({ state: "free" });
  });

  it("returns test premium when the allowlist is enabled", async () => {
    const verifiedAt = new Date().toISOString();
    const values = new Map([
      ["test-install:install-allowlisted-1:entitlement", JSON.stringify({ state: "premium", verifiedAt })],
    ]);
    const store = new SessionStore(
      redisMock(values) as never,
      loadEnv({
        NODE_ENV: "test",
        SESSION_JWT_SECRET: "a".repeat(32),
        OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
        ENABLE_TEST_INSTALL_ALLOWLIST: "true",
      }),
    );

    await expect(store.getEntitlement("install-allowlisted-1")).resolves.toEqual({ state: "premium", verifiedAt });
  });

  it("prefers real StoreKit entitlement over test allowlist", async () => {
    const realVerifiedAt = "2026-01-01T00:00:00.000Z";
    const testVerifiedAt = "2026-02-01T00:00:00.000Z";
    const values = new Map([
      ["install:install-allowlisted-1:entitlement", JSON.stringify({ state: "trial", verifiedAt: realVerifiedAt })],
      ["test-install:install-allowlisted-1:entitlement", JSON.stringify({ state: "premium", verifiedAt: testVerifiedAt })],
    ]);
    const store = new SessionStore(
      redisMock(values) as never,
      loadEnv({
        NODE_ENV: "test",
        SESSION_JWT_SECRET: "a".repeat(32),
        OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
        ENABLE_TEST_INSTALL_ALLOWLIST: "true",
      }),
    );

    await expect(store.getEntitlement("install-allowlisted-1")).resolves.toEqual({ state: "trial", verifiedAt: realVerifiedAt });
  });
});
