import { z } from "zod";
import { prisma } from "./db";

// Household sync payloads use the same shape as the iOS ExportBundle, so a free user's
// export can be pushed as-is the moment they upgrade. Rows are matched by natural keys
// (name, date+meal, etc.) so devices without server ids can still converge.

const ingredientSchema = z.object({ name: z.string(), quantity: z.number(), unit: z.string(), note: z.string().default("") });
export const bundleSchema = z.object({
  locations: z.array(z.object({ name: z.string(), icon: z.string().default("shippingbox") })).default([]),
  pantry: z.array(z.object({
    name: z.string(), quantity: z.number(), unit: z.string(), initialQuantity: z.number().default(1), reorderThreshold: z.number().default(0),
    category: z.string().default("Other"), expiryDate: z.coerce.date(), location: z.string().nullable().optional(),
  })).default([]),
  recipes: z.array(z.object({
    name: z.string(), instructions: z.string().default(""), servings: z.number().int().default(2), sourceURL: z.string().default(""), imageURL: z.string().default(""),
    prepMinutes: z.number().int().default(0), cookMinutes: z.number().int().default(0), tags: z.array(z.string()).default([]),
    nutritionPerServing: z.object({ calories: z.number(), protein: z.number(), carbs: z.number(), fat: z.number() }).nullable().optional(),
    ingredients: z.array(ingredientSchema).default([]),
  })).default([]),
  mealPlan: z.array(z.object({ date: z.coerce.date(), mealType: z.string(), recipe: z.string(), servings: z.number().int().default(2), note: z.string().default(""), isCooked: z.boolean().default(false) })).default([]),
  groceries: z.array(z.object({
    name: z.string(), quantity: z.number(), unit: z.string(), category: z.string().default("Other"), isChecked: z.boolean().default(false),
    source: z.string().default("manual"), note: z.string().default(""), priceCents: z.number().int().default(0), currencyCode: z.string().default(""),
  })).default([]),
  household: z.object({ name: z.string(), members: z.array(z.object({ name: z.string(), portionMultiplier: z.number().default(1), dietTags: z.string().default("") })) }).nullable().optional(),
});

export type SyncBundle = z.infer<typeof bundleSchema>;

export async function pushBundle(householdId: string, bundle: SyncBundle) {
  const counts = { recipes: 0, meals: 0, groceries: 0, pantry: 0, locations: 0 };

  for (const location of bundle.locations) {
    await prisma.pantryLocation.upsert({ where: { householdId_name: { householdId, name: location.name } }, update: { icon: location.icon }, create: { householdId, ...location } });
    counts.locations++;
  }
  const locations = await prisma.pantryLocation.findMany({ where: { householdId } });

  for (const recipe of bundle.recipes) {
    const existing = await prisma.recipe.findFirst({ where: { householdId, name: recipe.name, deletedAt: null } });
    const data = {
      name: recipe.name, instructions: recipe.instructions, servings: recipe.servings, sourceUrl: recipe.sourceURL, imageUrl: recipe.imageURL,
      prepMinutes: recipe.prepMinutes, cookMinutes: recipe.cookMinutes, tags: recipe.tags.join(", "),
      caloriesPerServing: recipe.nutritionPerServing?.calories ?? 0, proteinPerServing: recipe.nutritionPerServing?.protein ?? 0,
      carbsPerServing: recipe.nutritionPerServing?.carbs ?? 0, fatPerServing: recipe.nutritionPerServing?.fat ?? 0,
    };
    const ingredients = recipe.ingredients.map((i, index) => ({ ...i, sortOrder: index }));
    if (existing) {
      await prisma.recipe.update({ where: { id: existing.id }, data: { ...data, ingredients: { deleteMany: {}, create: ingredients } } });
    } else {
      await prisma.recipe.create({ data: { householdId, ...data, ingredients: { create: ingredients } } });
    }
    counts.recipes++;
  }
  const recipes = await prisma.recipe.findMany({ where: { householdId, deletedAt: null } });

  for (const meal of bundle.mealPlan) {
    const recipe = recipes.find((r) => r.name === meal.recipe);
    if (!recipe) continue;
    const date = new Date(Date.UTC(meal.date.getFullYear(), meal.date.getMonth(), meal.date.getDate()));
    const existing = await prisma.mealPlanEntry.findFirst({ where: { householdId, date, mealType: meal.mealType, recipeId: recipe.id, deletedAt: null } });
    if (existing) await prisma.mealPlanEntry.update({ where: { id: existing.id }, data: { servings: meal.servings, note: meal.note, isCooked: meal.isCooked } });
    else await prisma.mealPlanEntry.create({ data: { householdId, date, mealType: meal.mealType, recipeId: recipe.id, servings: meal.servings, note: meal.note, isCooked: meal.isCooked } });
    counts.meals++;
  }

  for (const grocery of bundle.groceries) {
    const existing = await prisma.groceryItem.findFirst({ where: { householdId, name: grocery.name, deletedAt: null } });
    const data = { quantity: grocery.quantity, unit: grocery.unit, category: grocery.category, isChecked: grocery.isChecked, source: grocery.source, note: grocery.note, priceCents: grocery.priceCents, currency: grocery.currencyCode };
    if (existing) await prisma.groceryItem.update({ where: { id: existing.id }, data });
    else await prisma.groceryItem.create({ data: { householdId, name: grocery.name, ...data } });
    counts.groceries++;
  }

  for (const item of bundle.pantry) {
    const location = locations.find((l) => l.name === item.location);
    const existing = await prisma.pantryItem.findFirst({ where: { householdId, name: item.name, locationId: location?.id ?? null, deletedAt: null } });
    const data = { quantity: item.quantity, unit: item.unit, initialQuantity: item.initialQuantity, reorderThreshold: item.reorderThreshold, category: item.category, expiryDate: item.expiryDate };
    if (existing) await prisma.pantryItem.update({ where: { id: existing.id }, data });
    else await prisma.pantryItem.create({ data: { householdId, name: item.name, locationId: location?.id, ...data } });
    counts.pantry++;
  }

  if (bundle.household) {
    await prisma.household.update({ where: { id: householdId }, data: { name: bundle.household.name } });
    for (const [index, member] of bundle.household.members.entries()) {
      const existing = await prisma.householdMember.findFirst({ where: { householdId, name: member.name } });
      if (existing) await prisma.householdMember.update({ where: { id: existing.id }, data: { portionMultiplier: member.portionMultiplier, dietTags: member.dietTags, sortOrder: index } });
      else await prisma.householdMember.create({ data: { householdId, name: member.name, portionMultiplier: member.portionMultiplier, dietTags: member.dietTags, sortOrder: index } });
    }
  }
  return counts;
}

/** Everything in the household, in ExportBundle shape. */
export async function pullBundle(householdId: string) {
  const household = await prisma.household.findUniqueOrThrow({
    where: { id: householdId },
    include: {
      members: { orderBy: { sortOrder: "asc" } },
      locations: true,
      pantry: { where: { deletedAt: null }, include: { location: true } },
      recipes: { where: { deletedAt: null }, include: { ingredients: { orderBy: { sortOrder: "asc" } } } },
      meals: { where: { deletedAt: null }, include: { recipe: true } },
      groceries: { where: { deletedAt: null } },
    },
  });
  return {
    version: 1,
    app: "mealy",
    exportedAt: new Date(),
    locations: household.locations.map((l) => ({ name: l.name, icon: l.icon })),
    pantry: household.pantry.map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, initialQuantity: p.initialQuantity, reorderThreshold: p.reorderThreshold, category: p.category, expiryDate: p.expiryDate, location: p.location?.name ?? null })),
    recipes: household.recipes.map((r) => ({
      name: r.name, instructions: r.instructions, servings: r.servings, sourceURL: r.sourceUrl, imageURL: r.imageUrl, prepMinutes: r.prepMinutes, cookMinutes: r.cookMinutes,
      tags: r.tags.split(",").map((t) => t.trim()).filter(Boolean),
      nutritionPerServing: r.caloriesPerServing || r.proteinPerServing || r.carbsPerServing || r.fatPerServing ? { calories: r.caloriesPerServing, protein: r.proteinPerServing, carbs: r.carbsPerServing, fat: r.fatPerServing } : null,
      ingredients: r.ingredients.map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit, note: i.note })),
    })),
    mealPlan: household.meals.filter((m) => m.recipe).map((m) => ({ date: m.date, mealType: m.mealType, recipe: m.recipe!.name, servings: m.servings, note: m.note, isCooked: m.isCooked })),
    groceries: household.groceries.map((g) => ({ name: g.name, quantity: g.quantity, unit: g.unit, category: g.category, isChecked: g.isChecked, source: g.source, note: g.note, priceCents: g.priceCents, currencyCode: g.currency })),
    household: { name: household.name, members: household.members.map((m) => ({ name: m.name, portionMultiplier: m.portionMultiplier, dietTags: m.dietTags })) },
  };
}
