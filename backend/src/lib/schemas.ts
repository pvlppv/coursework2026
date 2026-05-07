import { z } from "zod";

export const sessionRequestSchema = z.object({
  installId: z.string().min(16).max(128).regex(/^[A-Za-z0-9._:-]+$/).optional(),
});

export const signedTransactionRequestSchema = z.object({
  signedTransactionInfo: z.string().min(100),
});

const dialogueMessageSchema = z.object({
  id: z.string().optional(),
  role: z.enum(["user", "assistant"]),
  content: z.string().max(12_000),
  timestamp: z.string().optional(),
  durationMs: z.number().int().nonnegative().optional(),
});

const conversationSummarySchema = z.object({
  coreEntryText: z.string().max(12_000),
  coreInsight: z.string().max(4_000),
  nextOpenings: z.string().max(2_000).nullable().optional(),
  routingState: z.string().max(2_000).nullable().optional(),
  responseGuidance: z.string().max(2_000).nullable().optional(),
  stopSignals: z.array(z.string().max(300)).max(20).optional(),
  failedAngles: z.array(z.string().max(300)).max(20).optional(),
  signalQuality: z.enum(["strong", "moderate", "insufficient"]).optional(),
  anglesCovered: z.array(z.string().max(300)).max(30).optional(),
  evidenceTail: z.array(z.string().max(500)).max(20).optional(),
  summarizedMessageCount: z.number().int().nonnegative(),
  createdAt: z.string().optional(),
  totalMessageCount: z.number().int().nonnegative(),
});

const reflectionSettingsSchema = z.object({
  support_style: z.string().max(80).optional(),
  support_depth: z.string().max(80).optional(),
  primary_goals: z.array(z.string().max(80)).max(10).optional(),
});

export const goDeeperStreamRequestSchema = z.object({
  entryId: z.string().min(1).max(128),
  entryText: z.string().min(1).max(24_000),
  conversationHistory: z.array(dialogueMessageSchema).min(1).max(80),
  currentSummary: conversationSummarySchema.nullable().optional(),
  seedLensHint: z.string().max(1_000).nullable().optional(),
  reflectionSettings: reflectionSettingsSchema.nullable().optional(),
  locale: z
    .object({
      languageName: z.string().max(80).optional(),
      regionCode: z.string().max(8).nullable().optional(),
    })
    .optional(),
  client: z
    .object({
      suspiciousEnvironment: z.boolean().optional(),
    })
    .optional(),
});

const localeLanguageSchema = z.object({
  languageName: z.string().max(80).optional(),
});

const clientRuntimeSchema = z
  .object({
    suspiciousEnvironment: z.boolean().optional(),
  })
  .optional();

export const aiSummarizeRequestSchema = z.object({
  coreEntryText: z.string().min(1).max(24_000),
  newMessages: z.array(dialogueMessageSchema).min(1).max(80),
  previousSummary: conversationSummarySchema.nullable().optional(),
  totalSummarizedCount: z.number().int().positive().max(10_000),
  totalMessageCount: z.number().int().positive().max(10_000),
  locale: localeLanguageSchema.optional(),
  client: clientRuntimeSchema,
});

export const aiInsightsRequestSchema = z.object({
  entryText: z.string().min(1).max(24_000),
  messages: z.array(dialogueMessageSchema).min(1).max(120),
  locale: localeLanguageSchema.optional(),
  client: clientRuntimeSchema,
});

export const aiLanguageRepairRequestSchema = z.object({
  originalResponse: z.string().min(1).max(12_000),
  locale: localeLanguageSchema.optional(),
  client: clientRuntimeSchema,
});
