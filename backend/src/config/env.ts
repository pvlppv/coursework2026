import { z } from "zod";

const environmentSchema = z.object({
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  HOST: z.string().default("0.0.0.0"),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.string().default("info"),
  REDIS_URL: z.string().url().default("redis://localhost:6379"),
  SESSION_JWT_SECRET: z.string().min(32),
  OPENROUTER_API_KEY: z.string().min(20),
  OPENROUTER_BASE_URL: z.string().url().default("https://openrouter.ai/api/v1"),
  OPENROUTER_SITE_URL: z.string().url().default("https://sotie.app"),
  OPENROUTER_APP_NAME: z.string().default("Sotie"),
  OPENROUTER_MODEL: z.string().default("google/gemini-3-flash-preview"),
  OPENROUTER_FALLBACK_MODEL: z.string().default("moonshotai/kimi-k2-0905"),
  OPENROUTER_TTFT_TIMEOUT_MS: z.coerce.number().int().positive().default(5_000),
  OPENROUTER_REQUEST_TIMEOUT_MS: z.coerce.number().int().positive().default(30_000),
  APPLE_BUNDLE_ID: z.string().min(1).default("com.pvlppv.sotie.journal"),
  APPLE_ENVIRONMENT: z.enum(["Sandbox", "Production"]).default("Sandbox"),
  APPLE_APP_APPLE_ID: z.string().optional().default(""),
  APPLE_ROOT_CERTS_BASE64: z.string().optional().default(""),
  ENABLE_TEST_INSTALL_ALLOWLIST: z
    .enum(["true", "false"])
    .optional()
    .transform((value) => value === "true"),
  PREMIUM_DAILY_RESPONSE_LIMIT: z.coerce.number().int().positive().default(200),
  FREE_ONBOARDING_RESPONSE_LIMIT: z.coerce.number().int().nonnegative().default(3),
  REQUESTS_PER_MINUTE_LIMIT: z.coerce.number().int().positive().default(40),
  SUSPICIOUS_REQUESTS_PER_MINUTE_LIMIT: z.coerce.number().int().positive().default(8),
});

export type Env = z.infer<typeof environmentSchema>;

export function loadEnv(input: NodeJS.ProcessEnv = process.env): Env {
  const parsed = environmentSchema.safeParse(input);

  if (!parsed.success) {
    const issues = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ");
    throw new Error(`Invalid backend environment: ${issues}`);
  }

  if (parsed.data.APPLE_ENVIRONMENT === "Production" && !parsed.data.APPLE_APP_APPLE_ID) {
    throw new Error("APPLE_APP_APPLE_ID is required when APPLE_ENVIRONMENT=Production");
  }

  return parsed.data;
}
