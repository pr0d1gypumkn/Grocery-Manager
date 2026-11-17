import { ingredientKey, shortfalls, type Requirement, type StockItem } from "./ingredients";

// Automatic weekly planning. Scores each candidate recipe for a slot on: pantry coverage
// (use what's there), ingredient overlap with already-chosen meals (cheaper, less waste),
// diet tags, time budget per day, variety (no repeats within the week) and, when a price
// map is supplied, estimated cost against the weekly budget.

export interface PlannerRecipe {
  id: string;
  name: string;
  servings: number;
  tags: string[];
  totalMinutes: number;
  ingredients: Requirement[];
  caloriesPerServing?: number;
}

export interface PlannerOptions {
  weekStart: Date;
  slots: { dayOffset: number; mealType: "Breakfast" | "Lunch" | "Dinner" | "Snack"; maxMinutes?: number }[];
  servingsPerMeal: number;
  dietTags: string[];
  pantry: StockItem[];
  /** Estimated price per ingredient key, in cents for a "typical" purchase of it. */
  priceCentsByKey?: Map<string, number>;
  weeklyBudgetCents?: number;
  /** Recipe ids the user swapped out: never pick these. */
  excludeRecipeIds?: string[];
  /** Recipe ids already fixed in the week (kept, counted for overlap). */
  locked?: { recipeId: string; dayOffset: number; mealType: string }[];
}

export interface PlannedSlot {
  dayOffset: number;
  mealType: string;
  recipeId: string;
  servings: number;
  reasons: string[];
}

const MEAL_TAGS: Record<string, string[]> = {
  Breakfast: ["breakfast", "brunch"],
  Lunch: ["lunch", "salad", "wrap", "soup", "leftovers", "quick"],
  Dinner: ["dinner", "main", "meal-prep"],
  Snack: ["snack", "no-cook"],
};

function fitsDiet(recipe: PlannerRecipe, dietTags: string[]): boolean {
  const tags = recipe.tags.map((t) => t.toLowerCase());
  return dietTags.every((diet) => {
    const d = diet.toLowerCase();
    if (d === "vegetarian") return tags.includes("vegetarian") || tags.includes("vegan") || !recipe.ingredients.some((i) => /chicken|beef|pork|lamb|turkey|fish|salmon|shrimp|tuna|bacon|sausage|ham/.test(ingredientKey(i.name)));
    if (d === "vegan") return tags.includes("vegan") || !recipe.ingredients.some((i) => /chicken|beef|pork|lamb|turkey|fish|salmon|shrimp|tuna|bacon|sausage|ham|egg|milk|cheese|yogurt|butter|cream|honey/.test(ingredientKey(i.name)));
    if (d === "pescatarian") return !recipe.ingredients.some((i) => /chicken|beef|pork|lamb|turkey|bacon|sausage|ham/.test(ingredientKey(i.name)));
    if (d === "gluten-free") return !recipe.ingredients.some((i) => /flour|bread|pasta|tortilla|noodle|couscous|barley|pita/.test(ingredientKey(i.name)));
    if (d === "dairy-free") return !recipe.ingredients.some((i) => /milk|cheese|yogurt|butter|cream/.test(ingredientKey(i.name)));
    if (d === "nut-free") return !recipe.ingredients.some((i) => /almond|walnut|cashew|peanut|pecan|pistachio|hazelnut/.test(ingredientKey(i.name)));
    return true;
  });
}

export function estimateRecipeCost(recipe: PlannerRecipe, pantry: StockItem[], prices: Map<string, number>, servings: number): number {
  const scale = recipe.servings > 0 ? servings / recipe.servings : 1;
  const needed = shortfalls(recipe.ingredients.map((i) => ({ ...i, quantity: i.quantity * scale })), pantry);
  return needed.reduce((sum, line) => sum + (prices.get(ingredientKey(line.name)) ?? 0), 0);
}

export function planWeek(recipes: PlannerRecipe[], options: PlannerOptions): PlannedSlot[] {
  const excluded = new Set(options.excludeRecipeIds ?? []);
  const candidates = recipes.filter((r) => r.ingredients.length > 0 && !excluded.has(r.id) && fitsDiet(r, options.dietTags));
  const chosen: PlannedSlot[] = [];
  const usedKeys = new Set<string>();
  const usedRecipeIds = new Set<string>((options.locked ?? []).map((l) => l.recipeId));
  for (const lock of options.locked ?? []) {
    const recipe = recipes.find((r) => r.id === lock.recipeId);
    recipe?.ingredients.forEach((i) => usedKeys.add(ingredientKey(i.name)));
  }
  let spentCents = 0;
  const budget = options.weeklyBudgetCents ?? 0;

  for (const slot of options.slots) {
    if ((options.locked ?? []).some((l) => l.dayOffset === slot.dayOffset && l.mealType === slot.mealType)) continue;
    let best: { recipe: PlannerRecipe; score: number; reasons: string[]; cost: number } | undefined;
    for (const recipe of candidates) {
      if (usedRecipeIds.has(recipe.id)) continue;
      const reasons: string[] = [];
      let score = 0;
      const tags = recipe.tags.map((t) => t.toLowerCase());
      const mealFit = MEAL_TAGS[slot.mealType].some((t) => tags.includes(t));
      if (mealFit) { score += 3; reasons.push(`tagged for ${slot.mealType.toLowerCase()}`); }
      else if (slot.mealType === "Breakfast" && !tags.includes("breakfast")) score -= 4;

      const scale = recipe.servings > 0 ? options.servingsPerMeal / recipe.servings : 1;
      const needs = recipe.ingredients.map((i) => ({ ...i, quantity: i.quantity * scale }));
      const missing = shortfalls(needs, options.pantry);
      const coverage = needs.length ? 1 - missing.length / needs.length : 0;
      score += coverage * 4;
      if (coverage >= 0.6) reasons.push(`${Math.round(coverage * 100)}% already in your pantry`);

      const keys = recipe.ingredients.map((i) => ingredientKey(i.name));
      const overlap = keys.filter((k) => usedKeys.has(k)).length;
      score += Math.min(overlap, 4) * 0.75;
      if (overlap >= 2) reasons.push(`shares ${overlap} ingredients with the week`);

      if (slot.maxMinutes && recipe.totalMinutes > slot.maxMinutes) { score -= 3; }
      else if (slot.maxMinutes && recipe.totalMinutes > 0) reasons.push(`${recipe.totalMinutes} min fits your schedule`);

      let cost = 0;
      if (options.priceCentsByKey) {
        cost = estimateRecipeCost(recipe, options.pantry, options.priceCentsByKey, options.servingsPerMeal);
        if (budget > 0) {
          const remaining = budget - spentCents;
          const slotsLeft = options.slots.length - chosen.length;
          const perSlot = remaining / Math.max(slotsLeft, 1);
          if (cost > perSlot * 1.5) score -= 3;
          else if (cost <= perSlot) { score += 1.5; reasons.push(`about ${(cost / 100).toFixed(2)} for this meal`); }
        }
      }
      if (!best || score > best.score) best = { recipe, score, reasons, cost };
    }
    if (!best) continue;
    chosen.push({ dayOffset: slot.dayOffset, mealType: slot.mealType, recipeId: best.recipe.id, servings: Math.max(Math.round(options.servingsPerMeal), 1), reasons: best.reasons });
    usedRecipeIds.add(best.recipe.id);
    best.recipe.ingredients.forEach((i) => usedKeys.add(ingredientKey(i.name)));
    spentCents += best.cost;
    // Allow repeats only once every recipe has been used.
    if (usedRecipeIds.size >= candidates.length) usedRecipeIds.clear();
  }
  return chosen;
}
