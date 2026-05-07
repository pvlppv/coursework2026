import { Redis } from "ioredis";
import type { Env } from "../config/env.js";

export function createRedis(env: Env): Redis {
  return new Redis(env.REDIS_URL, {
    commandTimeout: 5_000,
    connectTimeout: 10_000,
    maxRetriesPerRequest: 3,
    lazyConnect: true,
    retryStrategy(times) {
      return Math.min(times * 50, 2_000);
    },
    reconnectOnError(error) {
      return error.message.includes("READONLY") ? 2 : false;
    },
  });
}
