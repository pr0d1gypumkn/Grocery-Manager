import { createHash } from "node:crypto";
import { SignJWT, createRemoteJWKSet, importPKCS8, jwtVerify } from "jose";

// Apple ID as the iOS login. Two ways in, both with no separate Mealy account:
// 1. Silent: the app sends a signed App Store transaction (see appstore.ts) and the
//    subscription itself identifies the user.
// 2. Sign in with Apple: for people without a subscription, e.g. a household member
//    joining someone else's plan. Apple requires revoking the token when the account is
//    deleted, which needs the Sign in with Apple key below.

const APPLE_ISSUER = "https://appleid.apple.com";
const JWKS = createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));

/** The iOS bundle ID: the `aud` of identity tokens and the `bundleId` of transactions. */
export function appleBundleID(): string {
  return process.env.APPLE_BUNDLE_ID ?? "work.pumpkinpatch.mealy";
}

export interface AppleIdentity {
  /** Stable per-app Apple user ID. */
  sub: string;
  /** Real or private-relay email. Apple only guarantees it on the first sign-in. */
  email?: string;
}

export function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

/**
 * Verifies a Sign in with Apple identity token: Apple's signature, issuer, audience, expiry,
 * and that its nonce is the SHA-256 of the raw nonce the app generated (stops replay).
 */
export async function verifyIdentityToken(identityToken: string, rawNonce: string): Promise<AppleIdentity> {
  const { payload } = await jwtVerify(identityToken, JWKS, { issuer: APPLE_ISSUER, audience: appleBundleID() });
  if (!payload.sub) throw new Error("Apple identity token has no subject");
  if (payload.nonce !== sha256Hex(rawNonce)) throw new Error("Apple identity token nonce mismatch");
  const email = typeof payload.email === "string" ? payload.email.toLowerCase() : undefined;
  return { sub: payload.sub, email };
}

function siwaConfigured(): boolean {
  return Boolean(process.env.APPLE_TEAM_ID && process.env.APPLE_SIWA_KEY_ID && process.env.APPLE_SIWA_PRIVATE_KEY);
}

/** Short-lived client secret for Apple's token and revoke endpoints. */
async function clientSecret(): Promise<string> {
  const pem = process.env.APPLE_SIWA_PRIVATE_KEY!.replace(/\\n/g, "\n");
  const key = await importPKCS8(pem, "ES256");
  return new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: process.env.APPLE_SIWA_KEY_ID! })
    .setIssuer(process.env.APPLE_TEAM_ID!)
    .setAudience(APPLE_ISSUER)
    .setSubject(appleBundleID())
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

/** Exchanges the one-time authorization code for a refresh token, kept so we can revoke later. */
export async function exchangeAuthorizationCode(code: string): Promise<string | null> {
  if (!siwaConfigured()) {
    console.warn("Sign in with Apple key not configured; account deletion can't revoke Apple tokens.");
    return null;
  }
  const response = await fetch(`${APPLE_ISSUER}/auth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: appleBundleID(), client_secret: await clientSecret(), code, grant_type: "authorization_code" }),
  });
  if (!response.ok) {
    console.error("Apple token exchange failed", response.status);
    return null;
  }
  const json = (await response.json()) as { refresh_token?: string };
  return json.refresh_token ?? null;
}

/** Revokes the user's Sign in with Apple grant (required on account deletion). */
export async function revokeAppleToken(refreshToken: string): Promise<boolean> {
  if (!siwaConfigured()) return false;
  const response = await fetch(`${APPLE_ISSUER}/auth/revoke`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: appleBundleID(), client_secret: await clientSecret(), token: refreshToken, token_type_hint: "refresh_token" }),
  });
  if (!response.ok) console.error("Apple token revoke failed", response.status);
  return response.ok;
}
