import { afterEach, describe, expect, it, vi } from "vitest";
import { loadEnv } from "../src/config/env.js";
import { OpenRouterService } from "../src/services/openrouter-service.js";

const env = loadEnv({
  SESSION_JWT_SECRET: "a".repeat(32),
  OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
  OPENROUTER_SITE_URL: "https://sotie.app",
  OPENROUTER_APP_NAME: "Sotie",
});

describe("OpenRouterService", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("uses current OpenRouter REST fields and attribution headers", async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ choices: [{ message: { content: "hello" } }] }), {
        headers: { "Content-Type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const service = new OpenRouterService(env);
    await service.generateChatCompletion({
      temperature: 0.7,
      maxTokens: 64,
      messages: [{ role: "user", content: "Hi" }],
      provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
    });

    expect(fetchMock).toHaveBeenCalledOnce();
    const [, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(init.headers).toMatchObject({
      "HTTP-Referer": "https://sotie.app",
      "X-OpenRouter-Title": "Sotie",
    });
    expect(JSON.parse(init.body as string)).toMatchObject({
      stream: false,
      max_completion_tokens: 64,
      provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
    });
    expect(JSON.parse(init.body as string)).not.toHaveProperty("max_tokens");
  });
});
