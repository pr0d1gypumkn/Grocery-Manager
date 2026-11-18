import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { prisma } from "@/lib/db";
import { stripeClient } from "@/lib/billing";
import { revokeAppleToken } from "@/lib/apple";
import { clearSessionCookie } from "@/lib/auth";

export const GET = withUser(async (_request, user) => {
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  return NextResponse.json({ id: profile.id, email: profile.email, region: profile.region, currency: profile.currency, unitSystem: profile.unitSystem, dietTags: profile.dietTags, weeklyBudgetCents: profile.weeklyBudgetCents });
});

/** Preferences, plus the appAccountToken the iOS app attaches to App Store purchases. */
export const PATCH = withUser(async (request, user) => {
  const body = z.object({
    region: z.enum(["US", "CA"]).optional(),
    unitSystem: z.enum(["metric", "imperial"]).optional(),
    dietTags: z.string().optional(),
    weeklyBudgetCents: z.number().int().min(0).optional(),
    appleAppAccountToken: z.string().uuid().optional(),
  }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "Invalid fields" }, { status: 400 });
  const data = { ...body.data, ...(body.data.region ? { currency: body.data.region === "CA" ? "CAD" : "USD" } : {}) };
  const profile = await prisma.user.update({ where: { id: user.id }, data });
  return NextResponse.json({ ok: true, region: profile.region, currency: profile.currency, unitSystem: profile.unitSystem });
});

/**
 * Permanently deletes the account (App Store Guideline 5.1.1(v)): households the user owns
 * and all their data, plus the user row (auth codes and subscription records cascade).
 * Memberships in other people's households are detached by the schema's SetNull.
 * Active Stripe subscriptions are cancelled and the Sign in with Apple grant is revoked;
 * App Store subscriptions can only be cancelled by the user.
 */
export const DELETE = withUser(async (_request, user) => {
  const stripe = stripeClient();
  if (stripe) {
    const active = await prisma.subscription.findMany({
      where: { userId: user.id, provider: "stripe", status: { in: ["active", "grace"] } },
    });
    for (const subscription of active) {
      await stripe.subscriptions.cancel(subscription.providerSubscriptionId).catch((error) => {
        console.error("Stripe cancel failed during account deletion", subscription.providerSubscriptionId, error);
      });
    }
  }
  const profile = await prisma.user.findUnique({ where: { id: user.id }, select: { appleRefreshToken: true } });
  if (profile?.appleRefreshToken) await revokeAppleToken(profile.appleRefreshToken);
  await prisma.$transaction([
    prisma.household.deleteMany({ where: { ownerId: user.id } }),
    prisma.user.delete({ where: { id: user.id } }),
  ]);
  await clearSessionCookie();
  return NextResponse.json({ ok: true });
});
