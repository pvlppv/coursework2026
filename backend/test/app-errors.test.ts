import { describe, expect, it, vi } from "vitest";
import { loadEnv } from "../src/config/env.js";
import type { EntitlementState, SessionPayload } from "../src/types/api.js";

process.env.SESSION_JWT_SECRET = "a".repeat(32);
process.env.OPENROUTER_API_KEY = "sk-or-test-key-with-enough-length";

const testEnv = loadEnv({
  NODE_ENV: "test",
  SESSION_JWT_SECRET: "a".repeat(32),
  OPENROUTER_API_KEY: "sk-or-test-key-with-enough-length",
});

function quotaReservation() {
  return {
    minuteKey: "minute-key",
    dayKey: "day-key",
    responsesToday: 1,
    maxResponsesPerDay: 3,
    isPremium: false,
  };
}

function quotaMock() {
  return {
    reserveAIRequest: vi.fn(async () => quotaReservation()),
    refundAIRequest: vi.fn(async () => undefined),
  };
}

describe("app error handling", () => {
  it("returns 400 for invalid Go Deeper request bodies", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: {
        verifySession: vi.fn(async () => session),
        getEntitlement: vi.fn(async (): Promise<EntitlementState> => ({ state: "free" })),
      } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: {} as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/go-deeper/stream",
        headers: { authorization: "Bearer test-token" },
        payload: {
          entryId: "entry-1",
          entryText: "I feel stuck.",
          conversationHistory: [],
        },
      });

      expect(response.statusCode).toBe(400);
      expect(response.json()).toMatchObject({
        error: { code: "invalid_request", message: "Invalid request body" },
      });
    } finally {
      await app.close();
    }
  });

  it("returns 403 when StoreKit rejects a signed transaction", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const { EntitlementService } = await import("../src/services/entitlement-service.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const entitlementService = new EntitlementService(testEnv);
    (entitlementService as unknown as { verifier: { verifyAndDecodeTransaction: () => Promise<never> } }).verifier = {
      verifyAndDecodeTransaction: vi.fn(async () => {
        throw new Error("invalid jws");
      }),
    };
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: {
        verifySession: vi.fn(async () => session),
        setEntitlement: vi.fn(),
      } as never,
      quota: quotaMock() as never,
      entitlements: entitlementService,
      openRouter: {} as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/entitlements/verify-transaction",
        headers: { authorization: "Bearer test-token" },
        payload: { signedTransactionInfo: "x".repeat(120) },
      });

      expect(response.statusCode).toBe(403);
      expect(response.json()).toMatchObject({
        error: { code: "invalid_transaction", message: "Transaction could not be verified" },
      });
    } finally {
      await app.close();
    }
  });

  it("builds summarization prompts on the backend", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi.fn(async () =>
      JSON.stringify({
        signalQuality: "moderate",
        coreInsight: "The user feels stuck.",
        routingState: "topic: myself",
        responseGuidance: "Clarify gently.",
        nextOpenings: "Name the next small step.",
        stopSignals: [],
        failedAngles: [],
        anglesCovered: ["avoidance"],
        evidenceTail: ["I feel stuck"],
      }),
    );
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn() } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/summarize-conversation",
        headers: { authorization: "Bearer test-token" },
        payload: {
          coreEntryText: "I feel stuck.",
          newMessages: [{ role: "user", content: "I keep avoiding it." }],
          totalSummarizedCount: 1,
          totalMessageCount: 1,
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json().content.coreInsight).toBe("The user feels stuck.");
      expect(generateChatCompletion).toHaveBeenCalledWith(
        expect.objectContaining({
          maxTokens: 2048,
          responseFormat: expect.objectContaining({ type: "json_schema" }),
          messages: expect.arrayContaining([
            expect.objectContaining({ role: "user", content: expect.stringContaining("# Original Entry - Data") }),
          ]),
        }),
        expect.any(AbortSignal),
      );
    } finally {
      await app.close();
    }
  });

  it("retries summarization once after invalid provider JSON", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi
      .fn()
      .mockResolvedValueOnce("not json")
      .mockResolvedValueOnce(
        JSON.stringify({
          signalQuality: "moderate",
          coreInsight: "The user feels stuck.",
          routingState: "topic: myself",
          responseGuidance: "Clarify gently.",
          nextOpenings: "Name the next small step.",
          stopSignals: [],
          failedAngles: [],
          anglesCovered: ["avoidance"],
          evidenceTail: ["I feel stuck"],
        }),
      );
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn() } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/summarize-conversation",
        headers: { authorization: "Bearer test-token" },
        payload: {
          coreEntryText: "I feel stuck.",
          newMessages: [{ role: "user", content: "I keep avoiding it." }],
          totalSummarizedCount: 1,
          totalMessageCount: 1,
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json().content.coreInsight).toBe("The user feels stuck.");
      expect(generateChatCompletion).toHaveBeenCalledTimes(2);
    } finally {
      await app.close();
    }
  });

  it("builds insights prompts on the backend", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi.fn(async () =>
      JSON.stringify({ what_happened: "A thing happened.", whats_underneath: "It stung.", what_matters_now: "One step is clear." }),
    );
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn() } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/insights",
        headers: { authorization: "Bearer test-token" },
        payload: {
          entryText: "I feel stuck.",
          messages: [{ role: "user", content: "I keep avoiding it." }],
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json().content.what_happened).toBe("A thing happened.");
      expect(generateChatCompletion).toHaveBeenCalledWith(
        expect.objectContaining({
          maxTokens: 256,
          messages: expect.arrayContaining([
            expect.objectContaining({ role: "user", content: expect.stringContaining("Generate a reflection takeaway") }),
          ]),
        }),
        expect.any(AbortSignal),
      );
    } finally {
      await app.close();
    }
  });

  it("retries insights up to three attempts", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi
      .fn()
      .mockRejectedValueOnce(new Error("provider timeout"))
      .mockResolvedValueOnce("not json")
      .mockResolvedValueOnce(
        JSON.stringify({
          what_happened: "A thing happened.",
          whats_underneath: "It stung.",
          what_matters_now: "One step is clear.",
        }),
      );
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn() } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/insights",
        headers: { authorization: "Bearer test-token" },
        payload: {
          entryText: "I feel stuck.",
          messages: [{ role: "user", content: "I keep avoiding it." }],
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json().content.what_happened).toBe("A thing happened.");
      expect(generateChatCompletion).toHaveBeenCalledTimes(3);
    } finally {
      await app.close();
    }
  });

  it("retries structured JSON when provider returns the wrong shape", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi
      .fn()
      .mockResolvedValueOnce(JSON.stringify({ what_happened: "A thing happened." }))
      .mockResolvedValueOnce(
        JSON.stringify({
          what_happened: "A thing happened.",
          whats_underneath: "It stung.",
          what_matters_now: "One step is clear.",
        }),
      );
    const quota = quotaMock();
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready", ping: vi.fn(async () => "PONG") } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn(async (): Promise<EntitlementState> => ({ state: "free" })) } as never,
      quota: quota as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/insights",
        headers: { authorization: "Bearer test-token" },
        payload: {
          entryText: "I feel stuck.",
          messages: [{ role: "user", content: "I keep avoiding it." }],
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(generateChatCompletion).toHaveBeenCalledTimes(2);
      expect(quota.refundAIRequest).not.toHaveBeenCalled();
    } finally {
      await app.close();
    }
  });

  it("refunds quota when structured AI generation never returns valid output", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi.fn(async () => "not json");
    const quota = quotaMock();
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready", ping: vi.fn(async () => "PONG") } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn(async (): Promise<EntitlementState> => ({ state: "free" })) } as never,
      quota: quota as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/summarize-conversation",
        headers: { authorization: "Bearer test-token" },
        payload: {
          coreEntryText: "I feel stuck.",
          newMessages: [{ role: "user", content: "I keep avoiding it." }],
          totalSummarizedCount: 1,
          totalMessageCount: 1,
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(500);
      expect(quota.refundAIRequest).toHaveBeenCalledWith(quotaReservation());
    } finally {
      await app.close();
    }
  });

  it("reserves quota for every non-streaming AI route", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const quota = quotaMock();
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready", ping: vi.fn(async () => "PONG") } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn(async (): Promise<EntitlementState> => ({ state: "free" })) } as never,
      quota: quota as never,
      entitlements: {} as never,
      openRouter: {
        generateChatCompletion: vi.fn(async () =>
          JSON.stringify({
            signalQuality: "moderate",
            coreInsight: "The user feels stuck.",
            routingState: "topic: myself",
            responseGuidance: "Clarify gently.",
            nextOpenings: "Name the next small step.",
            stopSignals: [],
            failedAngles: [],
            anglesCovered: ["avoidance"],
            evidenceTail: ["I feel stuck"],
          }),
        ),
      } as never,
    });

    try {
      await app.inject({
        method: "POST",
        url: "/v1/ai/summarize-conversation",
        headers: { authorization: "Bearer test-token" },
        payload: {
          coreEntryText: "I feel stuck.",
          newMessages: [{ role: "user", content: "I keep avoiding it." }],
          totalSummarizedCount: 1,
          totalMessageCount: 1,
        },
      });
      expect(quota.reserveAIRequest).toHaveBeenCalledTimes(1);
    } finally {
      await app.close();
    }
  });

  it("sets Retry-After for backend AI rate limits", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const { HttpError } = await import("../src/lib/errors.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: {
        verifySession: vi.fn(async () => session),
        getEntitlement: vi.fn(async (): Promise<EntitlementState> => ({ state: "free" })),
      } as never,
      quota: {
        reserveAIRequest: vi.fn(async () => {
          throw new HttpError(429, "rate_limited", "AI request burst limit reached", { retryAfterSeconds: 60 });
        }),
        refundAIRequest: vi.fn(async () => undefined),
      } as never,
      entitlements: {} as never,
      openRouter: {} as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/go-deeper/stream",
        headers: { authorization: "Bearer test-token" },
        payload: {
          entryId: "entry-1",
          entryText: "I feel stuck.",
          conversationHistory: [{ role: "user", content: "I feel stuck." }],
          reflectionSettings: {},
        },
      });

      expect(response.statusCode).toBe(429);
      expect(response.headers["retry-after"]).toBe("60");
      expect(response.json().error.details.retryAfterSeconds).toBe(60);
    } finally {
      await app.close();
    }
  });

  it("builds language repair prompts on the backend", async () => {
    const { buildApp } = await import("../src/http/app.js");
    const session: SessionPayload = { sessionId: "session-1", installId: "install-1" };
    const generateChatCompletion = vi.fn(async () => "Repaired response.");
    const app = await buildApp({
      env: testEnv,
      redis: { disconnect: vi.fn(), status: "ready" } as never,
      sessions: { verifySession: vi.fn(async () => session), getEntitlement: vi.fn() } as never,
      quota: quotaMock() as never,
      entitlements: {} as never,
      openRouter: { generateChatCompletion } as never,
    });

    try {
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/language-repair",
        headers: { authorization: "Bearer test-token" },
        payload: {
          originalResponse: "Wrong language.",
          locale: { languageName: "English" },
        },
      });

      expect(response.statusCode).toBe(200);
      expect(response.json()).toEqual({ text: "Repaired response." });
      expect(generateChatCompletion).toHaveBeenCalledWith(
        expect.objectContaining({
          messages: expect.arrayContaining([
            expect.objectContaining({ role: "user", content: expect.stringContaining("Wrong language.") }),
          ]),
        }),
        expect.any(AbortSignal),
      );
    } finally {
      await app.close();
    }
  });
});
