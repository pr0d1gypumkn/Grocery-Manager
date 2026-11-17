import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { prisma } from "@/lib/db";

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
