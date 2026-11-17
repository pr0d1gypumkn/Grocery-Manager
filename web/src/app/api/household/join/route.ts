import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { prisma } from "@/lib/db";

/** Joining is free for the invitee: the household owner's plan covers sharing. */
export const POST = withUser(async (request, user) => {
  const body = z.object({ code: z.string().min(4) }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "Invite code required" }, { status: 400 });
  const household = await prisma.household.findUnique({ where: { inviteCode: body.data.code.trim().toUpperCase() } });
  if (!household) return NextResponse.json({ error: "No household has that code" }, { status: 404 });
  await prisma.householdMember.deleteMany({ where: { userId: user.id, householdId: { not: household.id } } });
  await prisma.householdMember.upsert({
    where: { householdId_userId: { householdId: household.id, userId: user.id } },
    update: {},
    create: { householdId: household.id, userId: user.id, name: user.email.split("@")[0] },
  });
  return NextResponse.json({ householdId: household.id, name: household.name });
});
