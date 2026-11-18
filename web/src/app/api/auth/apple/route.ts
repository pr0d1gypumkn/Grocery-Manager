import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { exchangeAuthorizationCode, verifyIdentityToken, type AppleIdentity } from "@/lib/apple";
import { signToken, userFromRequest } from "@/lib/auth";
import { prisma } from "@/lib/db";

/**
 * Sign in with Apple for iOS users who don't subscribe themselves, such as a household
 * member joining someone else's plan. If the app is already signed in silently from a
 * purchase, the Apple ID is attached to that same user instead of creating a second one.
 */
export async function POST(request: NextRequest) {
  const body = z.object({
    identityToken: z.string().min(20),
    nonce: z.string().min(16),
    authorizationCode: z.string().optional(),
  }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "identityToken and nonce are required" }, { status: 400 });

  let identity: AppleIdentity;
  try {
    identity = await verifyIdentityToken(body.data.identityToken, body.data.nonce);
  } catch {
    return NextResponse.json({ error: "Sign in with Apple couldn't be verified." }, { status: 401 });
  }

  const current = await userFromRequest(request);
  let user = await prisma.user.findUnique({ where: { appleUserId: identity.sub } });
  if (!user && current) {
    const signedIn = await prisma.user.findUnique({ where: { id: current.id } });
    if (signedIn && !signedIn.appleUserId) {
      user = await prisma.user.update({ where: { id: signedIn.id }, data: { appleUserId: identity.sub } });
    }
  }
  if (!user && identity.email) {
    // Same person who used the web's email sign-in: link instead of duplicating.
    const byEmail = await prisma.user.findUnique({ where: { email: identity.email } });
    if (byEmail && !byEmail.appleUserId) {
      user = await prisma.user.update({ where: { id: byEmail.id }, data: { appleUserId: identity.sub } });
    }
  }
  if (!user) {
    // Keep the email only if no other account already uses it (emails are unique).
    const emailTaken = identity.email ? await prisma.user.findUnique({ where: { email: identity.email }, select: { id: true } }) : null;
    user = await prisma.user.create({ data: { appleUserId: identity.sub, email: emailTaken ? null : identity.email ?? null } });
  }

  if (body.data.authorizationCode && !user.appleRefreshToken) {
    const refreshToken = await exchangeAuthorizationCode(body.data.authorizationCode);
    if (refreshToken) user = await prisma.user.update({ where: { id: user.id }, data: { appleRefreshToken: refreshToken } });
  }

  const token = await signToken({ id: user.id, email: user.email });
  return NextResponse.json({ token, userId: user.id, email: user.email });
}
