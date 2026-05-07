export type DialogueRole = "user" | "assistant";

export interface DialogueMessage {
  id?: string;
  role: DialogueRole;
  content: string;
  timestamp?: string;
  durationMs?: number;
}

export type SignalQuality = "strong" | "moderate" | "insufficient";

export interface ConversationSummary {
  coreEntryText: string;
  coreInsight: string;
  nextOpenings?: string | null;
  routingState?: string | null;
  responseGuidance?: string | null;
  stopSignals?: string[];
  failedAngles?: string[];
  signalQuality?: SignalQuality;
  anglesCovered?: string[];
  evidenceTail?: string[];
  summarizedMessageCount: number;
  createdAt?: string;
  totalMessageCount: number;
}

export interface AIReflectionSettings {
  support_style?: string;
  support_depth?: string;
  primary_goals?: string[];
}

export interface GoDeeperStreamRequest {
  entryId: string;
  entryText: string;
  conversationHistory: DialogueMessage[];
  currentSummary?: ConversationSummary | null;
  seedLensHint?: string | null;
  reflectionSettings?: AIReflectionSettings | null;
  locale?: {
    languageName?: string;
    regionCode?: string | null;
  };
  client?: {
    suspiciousEnvironment?: boolean;
  };
}

export interface AISummarizeRequest {
  coreEntryText: string;
  newMessages: DialogueMessage[];
  previousSummary?: ConversationSummary | null;
  totalSummarizedCount: number;
  totalMessageCount: number;
  locale?: { languageName?: string };
  client?: { suspiciousEnvironment?: boolean };
}

export interface AIInsightsRequest {
  entryText: string;
  messages: DialogueMessage[];
  locale?: { languageName?: string };
  client?: { suspiciousEnvironment?: boolean };
}

export interface AILanguageRepairRequest {
  originalResponse: string;
  locale?: { languageName?: string };
  client?: { suspiciousEnvironment?: boolean };
}

export interface SessionPayload {
  sessionId: string;
  installId: string;
}

export interface EntitlementState {
  state: "free" | "trial" | "premium";
  productId?: string;
  originalTransactionId?: string;
  expiresAt?: string;
  verifiedAt?: string;
}
