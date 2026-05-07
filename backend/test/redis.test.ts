import { describe, expect, it, vi } from "vitest";
import { loadEnv } from "../src/config/env.js";

vi.mock("ioredis", () => ({
  Redis: vi.fn(function Redis(this: { url: string; options: Record<string, unknown> }, url: string, options: Record<string, unknown>) {
    this.url = url;
    this.options = options;
  }),
}));

describe("createRedis", () => {
  it("configures bounded reconnect and command timeouts", async () => {
    const { Redis } = await import("ioredis");
    const { createRedis } = await import("../src/lib/redis.js");
    const env = loadEnv({
      SESSION_JWT_SECRET: "a".repeat(32),
      OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
    });

    createRedis(env);

    expect(Redis).toHaveBeenCalledWith(
      "redis://localhost:6379",
      expect.objectContaining({
        commandTimeout: 5_000,
        connectTimeout: 10_000,
        maxRetriesPerRequest: 3,
        lazyConnect: true,
      }),
    );
  });
});
