import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { suggest } from "@/lib/suggestions";

const schema = z.object({
  savedNames: z.array(z.string()).optional(),
  savedTags: z.array(z.string()).optional(),
  pantry: z.array(z.object({ name: z.string(), quantity: z.number(), unit: z.string(), expiryDate: z.coerce.date() })).optional(),
  dietTags: z.array(z.string()).optional(),
  limit: z.number().int().min(1).max(20).optional(),
});

export const POST = withUser(async (request, user) => {
  const body = schema.safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "Invalid request" }, { status: 400 });
  const household = await householdFor(user.id);
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  const saved = await prisma.recipe.findMany({ where: { householdId: household.id, deletedAt: null }, select: { name: true, tags: true } });
  const pantry = body.data.pantry ?? (await prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null } })).map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, expiryDate: p.expiryDate }));
  const suggestions = suggest({
    savedNames: body.data.savedNames ?? saved.map((r) => r.name),
    savedTags: body.data.savedTags ?? saved.flatMap((r) => r.tags.split(",").map((t) => t.trim()).filter(Boolean)),
    pantry,
    dietTags: body.data.dietTags ?? profile.dietTags.split(",").map((t) => t.trim()).filter(Boolean),
    limit: body.data.limit,
  });
  return NextResponse.json({ suggestions });
}, "recipe_suggestions");
