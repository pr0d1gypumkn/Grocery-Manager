import { createHash, randomInt } from "node:crypto";
import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import type { NextRequest } from "next/server";
import { prisma } from "./db";

// Passwordless email codes. The same token works for the web (cookie) and the iOS app
// (Bearer header). No account is ever required for the free tier; this exists for Plus.

const SECRET = new TextEncoder().encode(process.env.AUTH_SECRET ?? "dev-secret-change-me");
const COOKIE = "mealy_session";
const TOKEN_DAYS = 90;

export interface SessionUser {
  id: string;
  email: string;
}

function hashCode(email: string, code: string): string {
  return createHash("sha256").update(`${email.toLowerCase()}:${code}`).digest("hex");
}

/** Creates (or finds) the user and issues a 6-digit code. Returns the code so the mailer can send it. */
export async function requestCode(emailRaw: string): Promise<{ code: string; userId: string }> {
  const email = emailRaw.trim().toLowerCase();
  const user = await prisma.user.upsert({ where: { email }, update: {}, create: { email } });
  const code = String(randomInt(0, 1_000_000)).padStart(6, "0");
  await prisma.authCode.create({
    data: { userId: user.id, codeHash: hashCode(email, code), expiresAt: new Date(Date.now() + 10 * 60 * 1000) },
  });
  return { code, userId: user.id };
}

export async function verifyCode(emailRaw: string, code: string): Promise<SessionUser | null> {
  const email = emailRaw.trim().toLowerCase();
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) return null;
  const record = await prisma.authCode.findFirst({
    where: { userId: user.id, codeHash: hashCode(email, code.trim()), usedAt: null, expiresAt: { gte: new Date() } },
    orderBy: { createdAt: "desc" },
  });
  if (!record) return null;
  await prisma.authCode.update({ where: { id: record.id }, data: { usedAt: new Date() } });
  return { id: user.id, email: user.email };
}

export async function signToken(user: SessionUser): Promise<string> {
  return new SignJWT({ email: user.email })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(user.id)
    .setIssuedAt()
    .setExpirationTime(`${TOKEN_DAYS}d`)
    .sign(SECRET);
}

export async function verifyToken(token: string): Promise<SessionUser | null> {
  try {
    const { payload } = await jwtVerify(token, SECRET);
    if (!payload.sub) return null;
    return { id: payload.sub, email: String(payload.email ?? "") };
  } catch {
    return null;
  }
}

/** Bearer token (apps) or session cookie (web). */
export async function userFromRequest(request: NextRequest): Promise<SessionUser | null> {
  const header = request.headers.get("authorization");
  if (header?.startsWith("Bearer ")) return verifyToken(header.slice(7));
  const cookie = request.cookies.get(COOKIE)?.value;
  return cookie ? verifyToken(cookie) : null;
}

export async function currentUser(): Promise<SessionUser | null> {
  const store = await cookies();
  const cookie = store.get(COOKIE)?.value;
  return cookie ? verifyToken(cookie) : null;
}

export async function setSessionCookie(token: string): Promise<void> {
  const store = await cookies();
  store.set(COOKIE, token, { httpOnly: true, sameSite: "lax", secure: process.env.NODE_ENV === "production", path: "/", maxAge: TOKEN_DAYS * 86400 });
}

export async function clearSessionCookie(): Promise<void> {
  const store = await cookies();
  store.delete(COOKIE);
}

/** The household a user belongs to, created on first use so every signed-in user has one. */
export async function householdFor(userId: string) {
  const membership = await prisma.householdMember.findFirst({ where: { userId }, include: { household: true } });
  if (membership) return membership.household;
  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  return prisma.household.create({
    data: {
      name: "My household",
      ownerId: userId,
      members: { create: { userId, name: user.email.split("@")[0], role: "owner" } },
    },
  });
}
