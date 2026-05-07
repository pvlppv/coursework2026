import cors from "@fastify/cors";
import rateLimit from "@fastify/rate-limit";
import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import type { Redis } from "ioredis";
import { z, ZodError } from "zod";
import type { Env } from "../config/env.js";
import { env } from "../config/runtime-env.js";
import { HttpError, isHttpError } from "../lib/errors.js";
import { createRedis } from "../lib/redis.js";
import {
  aiInsightsRequestSchema,
  aiLanguageRepairRequestSchema,
  aiSummarizeRequestSchema,
  goDeeperStreamRequestSchema,
  sessionRequestSchema,
  signedTransactionRequestSchema,
} from "../lib/schemas.js";
import { lineHasContentDelta } from "../lib/sse.js";
import {
  buildInsightsPrompt,
  buildInsightsSystemInstructions,
  buildLanguageRepairPrompt,
  buildLanguageRepairSystemInstructions,
  buildSummarizationPrompt,
  buildSummarizationSystemInstructions,
  insightsJsonSchema,
  summarizationJsonSchema,
} from "../prompts/ai-routes.js";
import { buildGoDeeperSystemInstructions, buildGoDeeperUserContent } from "../prompts/go-deeper.js";
import { EntitlementService } from "../services/entitlement-service.js";
import { OpenRouterService } from "../services/openrouter-service.js";
import { QuotaService } from "../services/quota-service.js";
import { SessionStore } from "../services/session-store.js";
import type {
  AIInsightsRequest,
  AILanguageRepairRequest,
  AISummarizeRequest,
  GoDeeperStreamRequest,
  SessionPayload,
} from "../types/api.js";

declare module "fastify" {
  interface FastifyRequest {
    session?: SessionPayload;
    timing?: {
      authMs?: number;
    };
  }
}

interface Dependencies {
  env: Env;
  redis: Redis;
  sessions: SessionStore;
  entitlements: EntitlementService;
  quota: QuotaService;
  openRouter: OpenRouterService;
}

type AIQuotaReservation = Awaited<ReturnType<QuotaService["reserveAIRequest"]>>;

const summarizationResponseSchema = z.object({
  signalQuality: z.enum(["strong", "moderate", "insufficient"]),
  coreInsight: z.string(),
  routingState: z.string(),
  responseGuidance: z.string(),
  nextOpenings: z.string(),
  stopSignals: z.array(z.string()),
  failedAngles: z.array(z.string()),
  anglesCovered: z.array(z.string()),
  evidenceTail: z.array(z.string()),
}).strict();

const insightsResponseSchema = z.object({
  what_happened: z.string(),
  whats_underneath: z.string(),
  what_matters_now: z.string(),
}).strict();

export async function buildApp(overrides?: Partial<Dependencies>): Promise<FastifyInstance> {
  const appEnv = overrides?.env ?? env;
  const redis = overrides?.redis ?? createRedis(appEnv);
  const deps: Dependencies = {
    env: appEnv,
    redis,
    sessions: overrides?.sessions ?? new SessionStore(redis, appEnv),
    entitlements: overrides?.entitlements ?? new EntitlementService(appEnv),
    quota: overrides?.quota ?? new QuotaService(redis, appEnv),
    openRouter: overrides?.openRouter ?? new OpenRouterService(appEnv),
  };

  const app = Fastify({
    logger: { level: appEnv.LOG_LEVEL },
    bodyLimit: 128 * 1024,
    disableRequestLogging: appEnv.NODE_ENV === "production",
  });

  app.decorate("deps", deps);
  app.decorate("readyCheck", async () => {
    await redis.ping();
  });

  app.setErrorHandler((error, request, reply) => {
    if (isHttpError(error)) {
      request.log.warn({ code: error.code, details: error.details }, error.message);
      if (error.statusCode === 429 && isRetryAfterDetails(error.details)) {
        reply.header("Retry-After", String(error.details.retryAfterSeconds));
      }
      return reply.status(error.statusCode).send({ error: { code: error.code, message: error.message, details: error.details } });
    }

    if (error instanceof ZodError) {
      request.log.warn({ issues: sanitizeZodIssues(error) }, "Invalid request body");
      return reply.status(400).send({
        error: { code: "invalid_request", message: "Invalid request body", details: sanitizeZodIssues(error) },
      });
    }

    request.log.error({ error: summarizeError(error) }, "Unhandled request error");
    return reply.status(500).send({ error: { code: "internal_error", message: "Internal server error" } });
  });

  await app.register(cors, { origin: false });
  await app.register(rateLimit, { max: 120, timeWindow: "1 minute" });

  app.addHook("onClose", async () => {
    redis.disconnect();
  });

  app.get("/health", async (request, reply) => {
    try {
      await redis.ping();
      return { ok: true, redis: "ready" };
    } catch {
      request.log.error({ redisStatus: redis.status }, "Health check failed");
      return reply.status(503).send({ ok: false, redis: redis.status });
    }
  });

  app.post("/v1/session", async (request, reply) => {
    const body = sessionRequestSchema.parse(request.body ?? {});
    const session = await deps.sessions.createSession(body.installId);
    reply.send(session);
  });

  app.get("/v1/me", { preHandler: auth(deps) }, async (request) => {
    const session = requireSession(request);
    return { session, entitlement: await deps.sessions.getEntitlement(session.installId) };
  });

  app.post("/v1/entitlements/verify-transaction", { preHandler: auth(deps) }, async (request, reply) => {
    const session = requireSession(request);
    const body = signedTransactionRequestSchema.parse(request.body ?? {});
    const entitlement = await deps.entitlements.verifySignedTransaction(body.signedTransactionInfo);
    await deps.sessions.setEntitlement(session.installId, entitlement);
    reply.send({ entitlement });
  });

  app.post("/v1/ai/go-deeper/stream", { preHandler: auth(deps) }, async (request, reply) => {
    const routeStartedAt = Date.now();
    const session = requireSession(request);
    const parseStartedAt = Date.now();
    const body = goDeeperStreamRequestSchema.parse(request.body) as GoDeeperStreamRequest;
    const parseMs = Date.now() - parseStartedAt;
    const quotaStartedAt = Date.now();
    const quota = await reserveAIQuota({ deps, request, session, suspiciousEnvironment: body.client?.suspiciousEnvironment });
    const quotaMs = Date.now() - quotaStartedAt;
    request.log.info(
      {
        route: "go-deeper-stream",
        authMs: request.timing?.authMs,
        parseMs,
        quotaMs,
        responsesToday: quota.responsesToday,
        maxResponsesPerDay: quota.maxResponsesPerDay,
        suspiciousEnvironment: body.client?.suspiciousEnvironment === true,
        conversationDepth: body.conversationHistory.length,
        hasSummary: body.currentSummary != null,
      },
      "AI route accepted",
    );

    const languageName = body.locale?.languageName ?? "English";
    const promptStartedAt = Date.now();
    const system = buildGoDeeperSystemInstructions(languageName, body.locale?.regionCode);
    const userContent = buildGoDeeperUserContent(body);
    const promptBuildMs = Date.now() - promptStartedAt;
    const abort = new AbortController();

    request.raw.on("close", () => {
      if (!reply.raw.writableEnded) {
        abort.abort();
      }
    });

    await streamWithRetries({
      deps,
      reply,
      abort,
      quota,
      routeStartedAt,
      routeTimings: {
        authMs: request.timing?.authMs,
        parseMs,
        quotaMs,
        promptBuildMs,
      },
      messages: [
        { role: "system", content: system },
        { role: "user", content: userContent },
      ],
    });
  });

  app.post("/v1/ai/summarize-conversation", { preHandler: auth(deps) }, async (request) => {
    const body = aiSummarizeRequestSchema.parse(request.body) as AISummarizeRequest;
    const session = requireSession(request);
    const quota = await reserveAIQuota({
      deps,
      request,
      session,
      scope: "summarize-conversation",
      suspiciousEnvironment: body.client?.suspiciousEnvironment,
    });
    const languageName = body.locale?.languageName ?? "English";
    request.log.info(
      {
        route: "summarize-conversation",
        newMessageCount: body.newMessages.length,
        totalSummarizedCount: body.totalSummarizedCount,
        totalMessageCount: body.totalMessageCount,
        hasPreviousSummary: body.previousSummary != null,
      },
      "AI route accepted",
    );
    const content = await generateStructuredJSONWithRetries({
      deps,
      request,
      route: "summarize-conversation",
      attempts: 2,
      quota,
      schema: summarizationResponseSchema,
      generate: (signal) =>
        deps.openRouter.generateChatCompletion(
          {
            temperature: 1.0,
            maxTokens: 2048,
            messages: [
              { role: "system", content: buildSummarizationSystemInstructions(languageName) },
              { role: "user", content: buildSummarizationPrompt({ ...body, languageName }) },
            ],
            reasoning: { effort: "low", exclude: true },
            provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
            responseFormat: jsonSchemaResponseFormat("summarization_response", summarizationJsonSchema),
          },
          signal,
        ),
    });

    return { content };
  });

  app.post("/v1/ai/insights", { preHandler: auth(deps) }, async (request) => {
    const body = aiInsightsRequestSchema.parse(request.body) as AIInsightsRequest;
    const session = requireSession(request);
    const quota = await reserveAIQuota({ deps, request, session, scope: "insights", suspiciousEnvironment: body.client?.suspiciousEnvironment });
    const languageName = body.locale?.languageName ?? "English";
    request.log.info(
      { route: "insights", messageCount: body.messages.length },
      "AI route accepted",
    );
    const content = await generateStructuredJSONWithRetries({
      deps,
      request,
      route: "insights",
      attempts: 3,
      quota,
      schema: insightsResponseSchema,
      generate: (signal) =>
        deps.openRouter.generateChatCompletion(
          {
            temperature: 0.7,
            maxTokens: 256,
            messages: [
              { role: "system", content: buildInsightsSystemInstructions(languageName) },
              { role: "user", content: buildInsightsPrompt(body.entryText, body.messages) },
            ],
            reasoning: { effort: "minimal", exclude: true },
            provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
            responseFormat: jsonSchemaResponseFormat("conversation_insights", insightsJsonSchema),
          },
          signal,
        ),
    });

    return { content };
  });

  app.post("/v1/ai/language-repair", { preHandler: auth(deps) }, async (request) => {
    const body = aiLanguageRepairRequestSchema.parse(request.body) as AILanguageRepairRequest;
    const session = requireSession(request);
    const quota = await reserveAIQuota({ deps, request, session, scope: "language-repair", suspiciousEnvironment: body.client?.suspiciousEnvironment });
    const languageName = body.locale?.languageName ?? "English";
    request.log.info({ route: "language-repair" }, "AI route accepted");
    const content = await generateStringWithRetries({
      deps,
      request,
      route: "language-repair",
      attempts: 2,
      quota,
      validate: (content) => content.trim() || null,
      generate: (signal) =>
        deps.openRouter.generateChatCompletion(
          {
            temperature: 1.0,
            maxTokens: 128,
            messages: [
              { role: "system", content: buildLanguageRepairSystemInstructions(languageName) },
              { role: "user", content: buildLanguageRepairPrompt(body.originalResponse, languageName) },
            ],
            reasoning: { effort: "minimal", exclude: true },
            provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
          },
          signal,
        ),
    });

    return { text: content };
  });

  return app;
}

function jsonSchemaResponseFormat(name: string, schema: unknown): Record<string, unknown> {
  return {
    type: "json_schema",
    json_schema: {
      name,
      strict: true,
      schema,
    },
  };
}

function auth(deps: Dependencies) {
  return async (request: FastifyRequest) => {
    const startedAt = Date.now();
    request.session = await deps.sessions.verifySession(request.headers.authorization);
    request.timing = { ...request.timing, authMs: Date.now() - startedAt };
  };
}

function requireSession(request: FastifyRequest): SessionPayload {
  if (!request.session) {
    throw new Error("Authenticated route missing session");
  }
  return request.session;
}

function isRetryAfterDetails(details: unknown): details is { retryAfterSeconds: number } {
  return (
    typeof details === "object" &&
    details !== null &&
    "retryAfterSeconds" in details &&
    typeof (details as { retryAfterSeconds?: unknown }).retryAfterSeconds === "number"
  );
}

function sanitizeZodIssues(error: ZodError): Array<{ path: string; code: string }> {
  return error.issues.map((issue) => ({ path: issue.path.join("."), code: issue.code }));
}

async function reserveAIQuota(params: {
  deps: Dependencies;
  request: FastifyRequest;
  session: SessionPayload;
  scope?: string;
  suspiciousEnvironment?: boolean;
}): Promise<AIQuotaReservation> {
  const entitlement = await params.deps.sessions.getEntitlement(params.session.installId);
  return params.deps.quota.reserveAIRequest({
    installId: params.session.installId,
    entitlement,
    scope: params.scope,
    suspiciousEnvironment: params.suspiciousEnvironment,
  });
}

function routeAbortSignal(request: FastifyRequest, timeoutMs: number): AbortSignal {
  const abort = new AbortController();
  const timeout = setTimeout(() => abort.abort(), timeoutMs);
  request.raw.on("close", () => abort.abort());
  abort.signal.addEventListener("abort", () => clearTimeout(timeout), { once: true });
  return abort.signal;
}

async function generateStructuredJSONWithRetries<T>(params: {
  deps: Dependencies;
  request: FastifyRequest;
  route: string;
  attempts: number;
  quota: AIQuotaReservation;
  schema: z.ZodType<T>;
  generate: (signal: AbortSignal) => Promise<string>;
}): Promise<T> {
  let lastError: unknown;
  const startedAt = Date.now();
  let succeeded = false;

  try {
    for (let attempt = 1; attempt <= params.attempts; attempt += 1) {
      try {
        const content = await params.generate(routeAbortSignal(params.request, params.deps.env.OPENROUTER_REQUEST_TIMEOUT_MS));
        const parsed = params.schema.parse(JSON.parse(content));
        succeeded = true;
        params.request.log.info(
          { route: params.route, attempt, durationMs: Date.now() - startedAt },
          "Structured AI route succeeded",
        );
        return parsed;
      } catch (error) {
        lastError = error;
        params.request.log.warn(
          { route: params.route, attempt, error: summarizeError(error) },
          "Structured AI route attempt failed",
        );
        if (attempt < params.attempts) {
          await sleep(250 * attempt);
        }
      }
    }

    throw lastError ?? new Error(`${params.route} failed`);
  } finally {
    if (!succeeded) {
      await params.deps.quota.refundAIRequest(params.quota).catch((error) => {
        params.request.log.error({ route: params.route, error: summarizeError(error) }, "AI quota refund failed");
      });
    }
  }
}

async function generateStringWithRetries(params: {
  deps: Dependencies;
  request: FastifyRequest;
  route: string;
  attempts: number;
  quota: AIQuotaReservation;
  generate: (signal: AbortSignal) => Promise<string>;
  validate: (content: string) => string | null;
}): Promise<string> {
  let lastError: unknown;
  const startedAt = Date.now();
  let succeeded = false;

  try {
    for (let attempt = 1; attempt <= params.attempts; attempt += 1) {
      try {
        const content = await params.generate(routeAbortSignal(params.request, params.deps.env.OPENROUTER_REQUEST_TIMEOUT_MS));
        const validated = params.validate(content);
        if (!validated) throw new HttpError(502, "invalid_ai_output", "AI returned invalid output");
        succeeded = true;
        params.request.log.info({ route: params.route, attempt, durationMs: Date.now() - startedAt }, "AI route succeeded");
        return validated;
      } catch (error) {
        lastError = error;
        params.request.log.warn({ route: params.route, attempt, error: summarizeError(error) }, "AI route attempt failed");
        if (attempt < params.attempts) {
          await sleep(250 * attempt);
        }
      }
    }

    throw lastError ?? new Error(`${params.route} failed`);
  } finally {
    if (!succeeded) {
      await params.deps.quota.refundAIRequest(params.quota).catch((error) => {
        params.request.log.error({ route: params.route, error: summarizeError(error) }, "AI quota refund failed");
      });
    }
  }
}

function setSSEHeaders(reply: FastifyReply, quota: { responsesToday: number; maxResponsesPerDay: number; isPremium: boolean }) {
  reply.raw.statusCode = 200;
  reply.raw.setHeader("Content-Type", "text/event-stream; charset=utf-8");
  reply.raw.setHeader("Cache-Control", "no-cache, no-transform");
  reply.raw.setHeader("Connection", "keep-alive");
  reply.raw.setHeader("X-Sotie-Responses-Today", String(quota.responsesToday));
  reply.raw.setHeader("X-Sotie-Responses-Limit", String(quota.maxResponsesPerDay));
  reply.raw.setHeader("X-Sotie-Premium", String(quota.isPremium));
  reply.hijack();
}

async function streamWithRetries(params: {
  deps: Dependencies;
  reply: FastifyReply;
  abort: AbortController;
  quota: AIQuotaReservation;
  routeStartedAt: number;
  routeTimings: {
    authMs?: number;
    parseMs: number;
    quotaMs: number;
    promptBuildMs: number;
  };
  messages: Array<{ role: "system" | "user" | "assistant"; content: string }>;
}) {
  const attempts = [
    {
      label: "primary",
      model: undefined,
      provider: { zdr: true, sort: "latency", preferred_max_latency: { p90: 3 } },
    },
    {
      label: "retry",
      model: undefined,
      provider: { zdr: true, sort: "latency" },
    },
    {
      label: "fallback",
      model: params.deps.env.OPENROUTER_FALLBACK_MODEL,
      provider: { zdr: true, sort: "latency" },
    },
  ];

  let lastError: unknown;
  let startedStreaming = false;

  try {
    for (const attempt of attempts) {
      const attemptAbort = new AbortController();
      const relayAbort = () => attemptAbort.abort();
      params.abort.signal.addEventListener("abort", relayAbort, { once: true });
      const attemptStartedAt = Date.now();

      try {
        params.reply.log.info(
          { route: "go-deeper-stream", attempt: attempt.label, model: attempt.model ?? "primary" },
          "AI stream attempt started",
        );
        const openRouterFetchStartedAt = Date.now();
        const providerResponse = await params.deps.openRouter.streamChatCompletion(
          {
            stream: true,
            temperature: 1.0,
            maxTokens: 1024,
            model: attempt.model,
            messages: params.messages,
            reasoning: { effort: "minimal", exclude: true },
            provider: attempt.provider,
          },
          attemptAbort.signal,
        );
        const openRouterHeadersMs = Date.now() - openRouterFetchStartedAt;

        const reader = providerResponse.body!.getReader();
        const firstContent = await readUntilFirstContent(reader, params.deps.env.OPENROUTER_TTFT_TIMEOUT_MS);
        const ttftMs = Date.now() - attemptStartedAt;
        const openRouterTtftMs = Date.now() - openRouterFetchStartedAt;
        const firstContentAfterHeadersMs = openRouterTtftMs - openRouterHeadersMs;
        const backendToFirstContentMs = Date.now() - params.routeStartedAt;

        if (firstContent.status === "timeout") {
          attemptAbort.abort();
          lastError = new Error(`TTFT timeout on ${attempt.label}`);
          params.reply.log.warn(
            {
              route: "go-deeper-stream",
              attempt: attempt.label,
              model: attempt.model ?? "primary",
              ttftMs,
              openRouterHeadersMs,
              openRouterTtftMs,
              firstContentAfterHeadersMs,
              backendToFirstContentMs,
              ...params.routeTimings,
            },
            "AI stream TTFT timeout before first token",
          );
          continue;
        }

        if (firstContent.status === "ended") {
          lastError = new Error(`OpenRouter stream ended before content on ${attempt.label}`);
          params.reply.log.warn(
            {
              route: "go-deeper-stream",
              attempt: attempt.label,
              model: attempt.model ?? "primary",
              ttftMs,
              openRouterHeadersMs,
              openRouterTtftMs,
              firstContentAfterHeadersMs,
              backendToFirstContentMs,
              ...params.routeTimings,
            },
            "AI stream ended before first content token",
          );
          continue;
        }

        startedStreaming = true;
        setSSEHeaders(params.reply, params.quota);
        for (const chunk of firstContent.chunks) {
          await writeChunk(params.reply, chunk);
        }
        await pipeReaderToReply(reader, params.reply, attemptAbort);
        params.reply.log.info(
          {
            route: "go-deeper-stream",
            attempt: attempt.label,
            model: attempt.model ?? "primary",
            ttftMs,
            openRouterHeadersMs,
            openRouterTtftMs,
            firstContentAfterHeadersMs,
            backendToFirstContentMs,
            ...params.routeTimings,
            durationMs: Date.now() - params.routeStartedAt,
            responsesToday: params.quota.responsesToday,
            maxResponsesPerDay: params.quota.maxResponsesPerDay,
            isPremium: params.quota.isPremium,
          },
          "AI stream succeeded",
        );
        return;
      } catch (error) {
        lastError = error;
        if (params.abort.signal.aborted) {
          return;
        }
        params.reply.log.warn(
          { route: "go-deeper-stream", attempt: attempt.label, model: attempt.model ?? "primary", error: summarizeError(error) },
          "AI stream attempt failed before first token",
        );
      } finally {
        params.abort.signal.removeEventListener("abort", relayAbort);
      }
    }

    throw lastError ?? new Error("OpenRouter stream failed before first token");
  } finally {
    if (!startedStreaming) {
      await params.deps.quota.refundAIRequest(params.quota).catch((error) => {
        params.reply.log.error({ route: "go-deeper-stream", error: summarizeError(error) }, "AI quota refund failed");
      });
    }
  }
}

function summarizeError(error: unknown): Record<string, unknown> {
  if (isHttpError(error)) {
    return { code: error.code, statusCode: error.statusCode, details: error.details };
  }
  if (error instanceof ZodError) {
    return { code: "invalid_shape", issues: sanitizeZodIssues(error) };
  }
  if (error instanceof SyntaxError) {
    return { code: "invalid_json" };
  }
  if (error instanceof Error) {
    return { name: error.name };
  }
  return { code: "unknown_error" };
}

type FirstContentResult =
  | { status: "content"; chunks: Uint8Array[] }
  | { status: "timeout"; chunks: Uint8Array[] }
  | { status: "ended"; chunks: Uint8Array[] };

async function readUntilFirstContent(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  timeoutMs: number,
): Promise<FirstContentResult> {
  const chunks: Uint8Array[] = [];
  const decoder = new TextDecoder();
  const deadline = Date.now() + timeoutMs;
  let bufferedText = "";

  while (true) {
    const remaining = deadline - Date.now();
    if (remaining <= 0) {
      return { status: "timeout", chunks };
    }

    const result = await Promise.race([reader.read(), sleep(remaining).then(() => "timeout" as const)]);
    if (result === "timeout") {
      return { status: "timeout", chunks };
    }

    if (result.done) {
      return { status: "ended", chunks };
    }

    chunks.push(result.value);
    bufferedText += decoder.decode(result.value, { stream: true });

    const lines = bufferedText.split(/\r?\n/);
    bufferedText = lines.pop() ?? "";
    if (lines.some(lineHasContentDelta)) {
      return { status: "content", chunks };
    }
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function pipeReaderToReply(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  reply: FastifyReply,
  abort: AbortController,
) {
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      await writeChunk(reply, value);
    }
  } catch (error) {
    abort.abort();
    throw error;
  } finally {
    reader.releaseLock();
    reply.raw.end();
  }
}

async function writeChunk(reply: FastifyReply, chunk: Uint8Array) {
  if (!reply.raw.write(Buffer.from(chunk))) {
    await new Promise<void>((resolve) => reply.raw.once("drain", resolve));
  }
}
