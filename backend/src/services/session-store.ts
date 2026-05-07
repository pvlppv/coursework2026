import { SignJWT, jwtVerify } from "jose";
import type { Redis } from "ioredis";
import { randomUUID } from "node:crypto";
import type { Env } from "../config/env.js";
import { HttpError } from "../lib/errors.js";
import type { EntitlementState, SessionPayload } from "../types/api.js";

const SESSION_TTL_SECONDS = 60 * 60 * 24 * 180;
const ENTITLEMENT_TTL_SECONDS = 60 * 60 * 24 * 35;
const TEST_INSTALL_ENTITLEMENT_TTL_SECONDS = 60 * 60 * 24 * 30;

export class SessionStore {
  private readonly jwtSecret: Uint8Array;

  constructor(
    private readonly redis: Redis,
    private readonly env: Env,
  ) {
    this.jwtSecret = new TextEncoder().encode(env.SESSION_JWT_SECRET);
  }

  async createSession(installId?: string): Promise<{ token: string; session: SessionPayload; entitlement: EntitlementState }> {
    const session: SessionPayload = {
      sessionId: randomUUID(),
      installId: installId ?? randomUUID(),
    };

    await this.redis.set(this.sessionKey(session.sessionId), JSON.stringify(session), "EX", SESSION_TTL_SECONDS);
    await this.redis.sadd(this.installSessionsKey(session.installId), session.sessionId);
    await this.redis.expire(this.installSessionsKey(session.installId), SESSION_TTL_SECONDS);

    const token = await new SignJWT({ ...session })
      .setProtectedHeader({ alg: "HS256", typ: "JWT" })
      .setSubject(session.sessionId)
      .setIssuedAt()
      .setExpirationTime(`${SESSION_TTL_SECONDS}s`)
      .sign(this.jwtSecret);

    return { token, session, entitlement: await this.getEntitlement(session.installId) };
  }

  async verifySession(authHeader: string | undefined): Promise<SessionPayload> {
    if (!authHeader?.startsWith("Bearer ")) {
      throw new HttpError(401, "missing_session", "Missing session bearer token");
    }

    const token = authHeader.slice("Bearer ".length);
    const verified = await jwtVerify(token, this.jwtSecret).catch(() => null);
    if (!verified) {
      throw new HttpError(401, "invalid_session", "Invalid session bearer token");
    }

    const payload = verified.payload as Partial<SessionPayload>;
    if (!payload.sessionId || !payload.installId) {
      throw new HttpError(401, "invalid_session", "Session token is missing required claims");
    }

    const stored = await this.redis.get(this.sessionKey(payload.sessionId));
    if (!stored) {
      throw new HttpError(401, "expired_session", "Session expired");
    }

    await this.redis.expire(this.sessionKey(payload.sessionId), SESSION_TTL_SECONDS);
    await this.redis.expire(this.installSessionsKey(payload.installId), SESSION_TTL_SECONDS);

    return { sessionId: payload.sessionId, installId: payload.installId };
  }

  async getEntitlement(installId: string): Promise<EntitlementState> {
    const stored = await this.redis.get(this.entitlementKey(installId));
    if (!stored) {
      const testEntitlement = await this.getTestInstallEntitlement(installId);
      if (testEntitlement) {
        return testEntitlement;
      }
      return { state: "free" };
    }

    const entitlement = JSON.parse(stored) as EntitlementState;
    if (entitlement.expiresAt && Date.parse(entitlement.expiresAt) <= Date.now()) {
      await this.redis.del(this.entitlementKey(installId));
      return { state: "free" };
    }

    return entitlement;
  }

  async setTestInstallEntitlement(installId: string, state: "trial" | "premium", ttlSeconds = TEST_INSTALL_ENTITLEMENT_TTL_SECONDS): Promise<void> {
    await this.redis.set(
      this.testInstallEntitlementKey(installId),
      JSON.stringify({ state, verifiedAt: new Date().toISOString() }),
      "EX",
      ttlSeconds,
    );
  }

  async removeTestInstallEntitlement(installId: string): Promise<void> {
    await this.redis.del(this.testInstallEntitlementKey(installId));
  }

  private async getTestInstallEntitlement(installId: string): Promise<EntitlementState | null> {
    if (!this.env.ENABLE_TEST_INSTALL_ALLOWLIST) {
      return null;
    }

    const stored = await this.redis.get(this.testInstallEntitlementKey(installId));
    if (!stored) {
      return null;
    }

    const entitlement = JSON.parse(stored) as EntitlementState;
    return entitlement.state === "trial" || entitlement.state === "premium" ? entitlement : null;
  }

  async setEntitlement(installId: string, entitlement: EntitlementState): Promise<void> {
    if (entitlement.originalTransactionId) {
      const key = this.transactionOwnerKey(entitlement.originalTransactionId);
      const owner = await this.redis.get(key);
      if (owner && owner !== installId) {
        throw new HttpError(403, "transaction_already_bound", "Transaction is already bound to another install");
      }
      await this.redis.set(key, installId, "EX", ENTITLEMENT_TTL_SECONDS);
    }

    await this.redis.set(this.entitlementKey(installId), JSON.stringify(entitlement), "EX", ENTITLEMENT_TTL_SECONDS);
  }

  private sessionKey(sessionId: string): string {
    return `session:${sessionId}`;
  }

  private installSessionsKey(installId: string): string {
    return `install:${installId}:sessions`;
  }

  private entitlementKey(installId: string): string {
    return `install:${installId}:entitlement`;
  }

  private testInstallEntitlementKey(installId: string): string {
    return `test-install:${installId}:entitlement`;
  }

  private transactionOwnerKey(originalTransactionId: string): string {
    return `transaction:${originalTransactionId}:install`;
  }
}
