import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { prisma } from "@/lib/db";

export const GET = withUser(async (_request, user) => {
  const household = await householdFor(user.id);
  const members = await prisma.householdMember.findMany({ where: { householdId: household.id }, orderBy: { sortOrder: "asc" }, include: { user: true } });
  return NextResponse.json({
    id: household.id,
    name: household.name,
    inviteCode: household.inviteCode,
    members: members.map((m) => ({ id: m.id, name: m.name, email: m.user?.email ?? null, role: m.role, portionMultiplier: m.portionMultiplier, dietTags: m.dietTags })),
  });
});
