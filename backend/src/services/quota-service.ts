import type { Redis } from "ioredis";
import type { Env } from "../config/env.js";
import { HttpError } from "../lib/errors.js";
import type { EntitlementState } from "../types/api.js";

const MINUTE_SECONDS = 60;

export class QuotaService {
  constructor(
    private readonly redis: Redis,
    private readonly env: Env,
  ) {}

  async reserveAIRequest(params: {
    installId: string;
    entitlement: EntitlementState;
    suspiciousEnvironment?: boolean;
    scope?: string;
  }): Promise<{ minuteKey: string; dayKey: string; responsesToday: number; maxResponsesPerDay: number; isPremium: boolean }> {
    const isPremium = params.entitlement.state === "premium" || params.entitlement.state === "trial";
    const dailyLimit = isPremium ? this.env.PREMIUM_DAILY_RESPONSE_LIMIT : this.env.FREE_ONBOARDING_RESPONSE_LIMIT;
    const minuteLimit = params.suspiciousEnvironment
      ? this.env.SUSPICIOUS_REQUESTS_PER_MINUTE_LIMIT
      : this.env.REQUESTS_PER_MINUTE_LIMIT;

    const minuteKey = `quota:${params.installId}:minute:${Math.floor(Date.now() / 60_000)}`;
    const scope = (params.scope ?? "response").replace(/[^a-z0-9_-]/gi, "_").slice(0, 64);
    const dayKey = `quota:${params.installId}:day:${scope}:${new Date().toISOString().slice(0, 10)}`;

    const result = (await this.redis.eval(
      RESERVE_QUOTA_SCRIPT,
      2,
      minuteKey,
      dayKey,
      String(minuteLimit),
      String(dailyLimit),
      String(MINUTE_SECONDS + 5),
      String(60 * 60 * 36),
    )) as [number, number, number];

    const [status, minuteCount, dayCount] = result;
    if (status === 1) {
      throw new HttpError(429, "rate_limited", "AI request burst limit reached", { retryAfterSeconds: MINUTE_SECONDS });
    }
    if (status === 2) {
      throw new HttpError(402, "quota_exceeded", "Daily AI response limit reached", {
        responsesToday: dayCount,
        maxResponsesPerDay: dailyLimit,
        isPremium,
      });
    }

    return { minuteKey, dayKey, responsesToday: dayCount, maxResponsesPerDay: dailyLimit, isPremium };
  }

  async refundAIRequest(reservation: { minuteKey: string; dayKey: string }): Promise<void> {
    await this.redis.eval(REFUND_QUOTA_SCRIPT, 2, reservation.minuteKey, reservation.dayKey);
  }
}

const RESERVE_QUOTA_SCRIPT = `
local minute = tonumber(redis.call("GET", KEYS[1]) or "0")
local day = tonumber(redis.call("GET", KEYS[2]) or "0")
local minuteLimit = tonumber(ARGV[1])
local dayLimit = tonumber(ARGV[2])

if minute >= minuteLimit then
  return {1, minute, day}
end
if day >= dayLimit then
  return {2, minute, day}
end

minute = redis.call("INCR", KEYS[1])
if minute == 1 then
  redis.call("EXPIRE", KEYS[1], tonumber(ARGV[3]))
end

day = redis.call("INCR", KEYS[2])
if day == 1 then
  redis.call("EXPIRE", KEYS[2], tonumber(ARGV[4]))
end

return {0, minute, day}
`;

const REFUND_QUOTA_SCRIPT = `
for i, key in ipairs(KEYS) do
  local value = tonumber(redis.call("GET", key) or "0")
  if value > 0 then
    redis.call("DECR", key)
  end
end
return 1
`;
