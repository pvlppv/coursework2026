import { Environment, SignedDataVerifier } from "@apple/app-store-server-library";
import type { Env } from "../config/env.js";
import { HttpError } from "../lib/errors.js";
import type { EntitlementState } from "../types/api.js";

const ALLOWED_PRODUCT_IDS = new Set([
  "com.pvlppv.sotie.journal.premium.monthly",
  "com.pvlppv.sotie.journal.premium.annual",
  "com.pvlppv.sotie.journal.premium.annual.discount",
]);

export class EntitlementService {
  private readonly verifier: SignedDataVerifier | null;

  constructor(private readonly env: Env) {
    this.verifier = this.createVerifier();
  }

  async verifySignedTransaction(signedTransactionInfo: string): Promise<EntitlementState> {
    if (!this.verifier) {
      throw new HttpError(503, "storekit_unconfigured", "StoreKit verification is not configured");
    }

    let transaction: Record<string, unknown>;
    try {
      transaction = (await (this.verifier as any).verifyAndDecodeTransaction(signedTransactionInfo)) as Record<
        string,
        unknown
      >;
    } catch {
      throw new HttpError(403, "invalid_transaction", "Transaction could not be verified");
    }

    const productId = stringField(transaction, "productId") ?? stringField(transaction, "productID");
    const bundleId = stringField(transaction, "bundleId") ?? stringField(transaction, "bundleID");
    const originalTransactionId = stringField(transaction, "originalTransactionId") ?? stringField(transaction, "originalTransactionID");
    const expiresDate = numberField(transaction, "expiresDate") ?? numberField(transaction, "expirationDate");
    const revocationDate = numberField(transaction, "revocationDate");

    if (bundleId !== this.env.APPLE_BUNDLE_ID) {
      throw new HttpError(403, "wrong_bundle", "Transaction belongs to a different bundle");
    }
    if (!productId || !ALLOWED_PRODUCT_IDS.has(productId)) {
      throw new HttpError(403, "unknown_product", "Transaction product is not a Sotie premium product");
    }
    if (revocationDate) {
      throw new HttpError(403, "revoked_transaction", "Transaction was revoked");
    }
    if (expiresDate && expiresDate <= Date.now()) {
      throw new HttpError(403, "expired_transaction", "Transaction is expired");
    }

    const offerType = numberField(transaction, "offerType");
    const state = offerType === 1 ? "trial" : "premium";

    return {
      state,
      productId,
      originalTransactionId,
      expiresAt: expiresDate ? new Date(expiresDate).toISOString() : undefined,
      verifiedAt: new Date().toISOString(),
    };
  }

  private createVerifier(): SignedDataVerifier | null {
    const rootCerts = parseRootCertificates(this.env.APPLE_ROOT_CERTS_BASE64);
    if (rootCerts.length === 0) {
      return null;
    }

    const environment = this.env.APPLE_ENVIRONMENT === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const appAppleId = this.env.APPLE_ENVIRONMENT === "Production" ? Number(this.env.APPLE_APP_APPLE_ID) : undefined;
    return new SignedDataVerifier(rootCerts, true, environment, this.env.APPLE_BUNDLE_ID, appAppleId);
  }
}

function parseRootCertificates(encoded: string): Buffer[] {
  if (!encoded.trim()) {
    return [];
  }

  const decoded = Buffer.from(encoded, "base64").toString("utf8");
  const matches = decoded.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) ?? [];
  return matches.map((cert) => Buffer.from(cert));
}

function stringField(source: Record<string, unknown>, key: string): string | undefined {
  const value = source[key];
  return typeof value === "string" && value.length > 0 ? value : undefined;
}

function numberField(source: Record<string, unknown>, key: string): number | undefined {
  const value = source[key];
  if (typeof value === "number") return value;
  if (typeof value === "string" && /^\d+$/.test(value)) return Number(value);
  return undefined;
}
