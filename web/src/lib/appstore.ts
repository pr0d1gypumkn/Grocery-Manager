import { createHash, X509Certificate } from "node:crypto";
import { compactVerify, decodeProtectedHeader, importX509 } from "jose";

// App Store Server Notifications V2 arrive as signed JWS payloads. We verify the leaf
// certificate's signature over the payload and that the chain ends at Apple's root.
// Apple Root CA - G3, SHA-256 fingerprint (public, from apple.com/certificateauthority).
const APPLE_ROOT_FINGERPRINTS = new Set([
  "63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179",
]);

export interface DecodedTransaction {
  originalTransactionId: string;
  transactionId: string;
  productId: string;
  expiresDate?: number;
  revocationDate?: number;
  appAccountToken?: string;
  environment?: string;
}

export interface DecodedRenewalInfo {
  autoRenewStatus?: number;
  isInBillingRetryPeriod?: boolean;
  gracePeriodExpiresDate?: number;
  expirationIntent?: number;
}

export interface DecodedNotification {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  data?: { signedTransactionInfo?: string; signedRenewalInfo?: string; environment?: string };
}

function fingerprint(cert: X509Certificate): string {
  return createHash("sha256").update(cert.raw).digest("hex").toUpperCase();
}

/** Verifies a JWS signed with an Apple x5c chain and returns its JSON payload. */
export async function verifyAppleJWS<T>(jws: string, options: { allowUnverified?: boolean } = {}): Promise<T> {
  const header = decodeProtectedHeader(jws);
  const chain = header.x5c;
  if (!chain || chain.length === 0) throw new Error("Apple JWS is missing its certificate chain");
  const certs = chain.map((b64) => new X509Certificate(Buffer.from(b64, "base64")));
  const root = certs[certs.length - 1];
  const rootTrusted = APPLE_ROOT_FINGERPRINTS.has(fingerprint(root));
  const chainValid = certs.every((cert, index) => index === certs.length - 1 || cert.checkIssued(certs[index + 1]));
  if (!(rootTrusted && chainValid) && !options.allowUnverified) {
    throw new Error("Apple certificate chain is not trusted");
  }
  const key = await importX509(certs[0].toString(), header.alg ?? "ES256");
  const { payload } = await compactVerify(jws, key);
  return JSON.parse(new TextDecoder().decode(payload)) as T;
}

/** Turns a notification into the subscription row we store. */
export function subscriptionStateFrom(transaction: DecodedTransaction, renewal: DecodedRenewalInfo | undefined, notificationType: string) {
  const expires = transaction.expiresDate ? new Date(transaction.expiresDate) : new Date(0);
  const grace = renewal?.gracePeriodExpiresDate ? new Date(renewal.gracePeriodExpiresDate) : null;
  const now = new Date();
  let status = "active";
  if (transaction.revocationDate || notificationType === "REFUND" || notificationType === "REVOKE") status = "revoked";
  else if (expires < now && grace && grace >= now) status = "grace";
  else if (expires < now) status = "expired";
  return {
    status,
    currentPeriodEnd: status === "grace" && grace ? grace : expires,
    isInGracePeriod: status === "grace",
    environment: transaction.environment === "Sandbox" ? "sandbox" : "production",
  };
}
