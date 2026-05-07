import { createRedis } from "../lib/redis.js";
import { loadEnv } from "../config/env.js";

const INSTALL_ID_PATTERN = /^[A-Za-z0-9._:-]{16,128}$/;

async function main(): Promise<void> {
  const [command, installId, ...args] = process.argv.slice(2);
  if (!command || !installId || !["approve", "revoke", "status"].includes(command)) {
    usage();
    process.exit(1);
  }
  if (!INSTALL_ID_PATTERN.test(installId)) {
    throw new Error("Install ID must be 16-128 chars and contain only letters, numbers, dots, underscores, colons, or hyphens.");
  }

  const env = loadEnv();
  const redis = createRedis(env);
  const key = `test-install:${installId}:entitlement`;

  try {
    if (command === "approve") {
      const state = readOption(args, "--state") ?? "premium";
      if (state !== "premium" && state !== "trial") {
        throw new Error("--state must be premium or trial.");
      }
      const days = Number(readOption(args, "--days") ?? "30");
      if (!Number.isInteger(days) || days < 1 || days > 365) {
        throw new Error("--days must be an integer from 1 to 365.");
      }

      const ttlSeconds = days * 24 * 60 * 60;
      await redis.set(key, JSON.stringify({ state, verifiedAt: new Date().toISOString() }), "EX", ttlSeconds);
      console.log(`Approved ${installId} as ${state} for ${days} day(s).`);
      return;
    }

    if (command === "revoke") {
      await redis.del(key);
      console.log(`Revoked test entitlement for ${installId}.`);
      return;
    }

    const [value, ttl] = await Promise.all([redis.get(key), redis.ttl(key)]);
    if (!value) {
      console.log(`${installId} is not allowlisted.`);
      return;
    }
    console.log(`${installId} is allowlisted: ${value} ttlSeconds=${ttl}`);
  } finally {
    redis.disconnect();
  }
}

function readOption(args: string[], name: string): string | undefined {
  const index = args.indexOf(name);
  return index >= 0 ? args[index + 1] : undefined;
}

function usage(): void {
  console.error("Usage:");
  console.error("  npm run test-install -- approve <installId> [--state premium|trial] [--days 30]");
  console.error("  npm run test-install -- revoke <installId>");
  console.error("  npm run test-install -- status <installId>");
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
