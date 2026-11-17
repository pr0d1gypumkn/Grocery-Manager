import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { prisma } from "@/lib/db";
import { ingredientKey } from "@/lib/ingredients";
import { planWeek, type PlannerRecipe } from "@/lib/planner";
import { bestQuotes } from "@/lib/prices/registry";

const schema = z.object({
  weekStart: z.coerce.date(),
  slots: z.array(z.object({ dayOffset: z.number().int().min(0).max(6), mealType: z.enum(["Breakfast", "Lunch", "Dinner", "Snack"]), maxMinutes: z.number().int().optional() })).optional(),
  servingsPerMeal: z.number().optional(),
  dietTags: z.array(z.string()).optional(),
  excludeRecipeIds: z.array(z.string()).optional(),
  locked: z.array(z.object({ recipeId: z.string(), dayOffset: z.number().int(), mealType: z.string() })).optional(),
  /** Devices that don't sync can send their recipes and pantry inline. */
  recipes: z.array(z.object({ id: z.string(), name: z.string(), servings: z.number().int(), tags: z.array(z.string()).default([]), totalMinutes: z.number().int().default(0), ingredients: z.array(z.object({ name: z.string(), quantity: z.number(), unit: z.string() })) })).optional(),
  pantry: z.array(z.object({ name: z.string(), quantity: z.number(), unit: z.string(), expiryDate: z.coerce.date() })).optional(),
});

export const POST = withUser(async (request, user) => {
  const body = schema.safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "weekStart required", issues: body.error.issues.slice(0, 3) }, { status: 400 });
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  const household = await householdFor(user.id);

  let recipes: PlannerRecipe[] = body.data.recipes ?? [];
  if (recipes.length === 0) {
    const rows = await prisma.recipe.findMany({ where: { householdId: household.id, deletedAt: null }, include: { ingredients: true } });
    recipes = rows.map((r) => ({ id: r.id, name: r.name, servings: r.servings, tags: r.tags.split(",").map((t) => t.trim()).filter(Boolean), totalMinutes: r.prepMinutes + r.cookMinutes, ingredients: r.ingredients.map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit })), caloriesPerServing: r.caloriesPerServing }));
  }
  let pantry = body.data.pantry ?? [];
  if (pantry.length === 0) {
    pantry = (await prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null } })).map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, expiryDate: p.expiryDate }));
  }
  const members = await prisma.householdMember.findMany({ where: { householdId: household.id } });
  const servingsPerMeal = body.data.servingsPerMeal ?? Math.max(members.reduce((sum, m) => sum + m.portionMultiplier, 0), 2);
  const dietTags = body.data.dietTags ?? [...new Set([...profile.dietTags.split(","), ...members.flatMap((m) => m.dietTags.split(","))].map((t) => t.trim()).filter(Boolean))];

  const region = profile.region as "US" | "CA";
  const allIngredients = [...new Map(recipes.flatMap((r) => r.ingredients).map((i) => [ingredientKey(i.name), i])).values()];
  const quotes = await bestQuotes(region, allIngredients);
  const priceCentsByKey = new Map([...quotes.entries()].map(([key, quote]) => [key, quote.priceCents]));

  const slots = body.data.slots ?? [0, 1, 2, 3, 4, 5, 6].flatMap((dayOffset) => [{ dayOffset, mealType: "Dinner" as const }, ...(dayOffset < 5 ? [{ dayOffset, mealType: "Lunch" as const, maxMinutes: 20 }] : [])]);
  const plan = planWeek(recipes, { weekStart: body.data.weekStart, slots, servingsPerMeal, dietTags, pantry, priceCentsByKey, weeklyBudgetCents: profile.weeklyBudgetCents, excludeRecipeIds: body.data.excludeRecipeIds, locked: body.data.locked });

  const estimatedCents = plan.reduce((sum, slot) => {
    const recipe = recipes.find((r) => r.id === slot.recipeId);
    return sum + (recipe?.ingredients.reduce((s, i) => s + (priceCentsByKey.get(ingredientKey(i.name)) ?? 0), 0) ?? 0);
  }, 0);

  return NextResponse.json({
    weekStart: body.data.weekStart,
    servingsPerMeal,
    dietTags,
    estimatedCents,
    currency: region === "CA" ? "CAD" : "USD",
    budgetCents: profile.weeklyBudgetCents,
    slots: plan.map((slot) => ({ ...slot, recipeName: recipes.find((r) => r.id === slot.recipeId)?.name ?? "" })),
  });
}, "automatic_planning");
