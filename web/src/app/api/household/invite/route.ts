import { randomBytes } from "node:crypto";
import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { prisma } from "@/lib/db";

/** Rotates the invite code. Sharing itself is the Plus feature; the owner must have it. */
export const POST = withUser(async (_request, user) => {
  const household = await householdFor(user.id);
  if (household.ownerId !== user.id) return NextResponse.json({ error: "Only the owner can invite" }, { status: 403 });
  const inviteCode = randomBytes(4).toString("hex").toUpperCase();
  await prisma.household.update({ where: { id: household.id }, data: { inviteCode } });
  return NextResponse.json({ inviteCode });
}, "household_sharing");
