import { describe, expect, it } from "vitest";
import { planWeek, type PlannerRecipe } from "@/lib/planner";
import { MockPriceSource } from "@/lib/prices/mock";
import { suggest } from "@/lib/suggestions";

const future = new Date(Date.now() + 10 * 86400 * 1000);
const recipes: PlannerRecipe[] = [
  { id: "a", name: "Chicken bowls", servings: 4, tags: ["dinner"], totalMinutes: 45, ingredients: [{ name: "chicken thighs", quantity: 700, unit: "g" }, { name: "rice", quantity: 300, unit: "g" }] },
  { id: "b", name: "Curry", servings: 4, tags: ["dinner", "vegetarian"], totalMinutes: 35, ingredients: [{ name: "chickpeas", quantity: 2, unit: "item" }, { name: "rice", quantity: 300, unit: "g" }, { name: "spinach", quantity: 200, unit: "g" }] },
  { id: "c", name: "Oats", servings: 2, tags: ["breakfast"], totalMinutes: 5, ingredients: [{ name: "oats", quantity: 100, unit: "g" }, { name: "milk", quantity: 250, unit: "ml" }] },
  { id: "d", name: "Salad", servings: 2, tags: ["lunch", "vegan"], totalMinutes: 15, ingredients: [{ name: "quinoa", quantity: 200, unit: "g" }, { name: "spinach", quantity: 100, unit: "g" }] },
];

describe("automatic planning", () => {
  it("fills slots, respects diet and avoids repeats", () => {
    const plan = planWeek(recipes, {
      weekStart: new Date(), servingsPerMeal: 2, dietTags: ["vegetarian"], pantry: [{ name: "spinach", quantity: 500, unit: "g", expiryDate: future }],
      slots: [{ dayOffset: 0, mealType: "Dinner" }, { dayOffset: 0, mealType: "Breakfast" }, { dayOffset: 1, mealType: "Lunch", maxMinutes: 20 }],
    });
    expect(plan).toHaveLength(3);
    expect(plan.map((s) => s.recipeId)).not.toContain("a");
    expect(plan.find((s) => s.mealType === "Dinner")?.recipeId).toBe("b");
    expect(plan.find((s) => s.mealType === "Breakfast")?.recipeId).toBe("c");
    expect(new Set(plan.map((s) => s.recipeId)).size).toBe(3);
  });
  it("honours swaps and locked meals", () => {
    const plan = planWeek(recipes, { weekStart: new Date(), servingsPerMeal: 2, dietTags: [], pantry: [], excludeRecipeIds: ["b"], locked: [{ recipeId: "a", dayOffset: 0, mealType: "Dinner" }], slots: [{ dayOffset: 0, mealType: "Dinner" }, { dayOffset: 1, mealType: "Dinner" }] });
    expect(plan).toHaveLength(1);
    expect(plan[0].dayOffset).toBe(1);
    expect(["a", "b"]).not.toContain(plan[0].recipeId);
  });
});

describe("mock prices", () => {
  it("quotes known items with regional currency and sales", async () => {
    const quotes = await new MockPriceSource("CA").quotes([{ name: "chicken thighs", quantity: 700, unit: "g" }, { name: "unicorn dust", quantity: 1, unit: "item" }]);
    expect(quotes).toHaveLength(1);
    expect(quotes[0].currency).toBe("CAD");
    expect(quotes[0].priceCents).toBeGreaterThan(0);
  });
});

describe("suggestions", () => {
  it("skips saved recipes and favours pantry matches", () => {
    const result = suggest({ savedNames: ["Honey Garlic Salmon"], savedTags: ["pescatarian"], pantry: [{ name: "shrimp", quantity: 400, unit: "g", expiryDate: future }, { name: "pasta", quantity: 500, unit: "g", expiryDate: future }], dietTags: [] });
    expect(result.map((s) => s.recipe.name)).not.toContain("Honey Garlic Salmon");
    expect(result[0].recipe.name).toBe("Garlic Butter Shrimp Pasta");
  });
});
