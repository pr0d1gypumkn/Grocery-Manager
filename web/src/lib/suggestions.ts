import { ingredientKey, type StockItem } from "./ingredients";
import catalog from "./catalog.json";

// Recipe ideas the user hasn't saved. The catalog is a small built-in set so the feature
// works offline; swap `catalog.json` for a licensed recipe feed later.

export interface CatalogRecipe {
  id: string;
  name: string;
  servings: number;
  tags: string[];
  prepMinutes: number;
  cookMinutes: number;
  ingredients: { name: string; quantity: number; unit: string }[];
  instructions: string[];
  sourceUrl?: string;
}

export interface Suggestion {
  recipe: CatalogRecipe;
  score: number;
  reasons: string[];
}

export function suggest(options: { savedNames: string[]; savedTags: string[]; pantry: StockItem[]; dietTags: string[]; limit?: number }): Suggestion[] {
  const saved = new Set(options.savedNames.map((n) => n.toLowerCase()));
  const tasteTags = new Map<string, number>();
  for (const tag of options.savedTags.map((t) => t.toLowerCase())) tasteTags.set(tag, (tasteTags.get(tag) ?? 0) + 1);
  const pantryKeys = new Set(options.pantry.filter((p) => p.quantity > 0).map((p) => ingredientKey(p.name)));
  const diets = options.dietTags.map((d) => d.toLowerCase());

  return (catalog as CatalogRecipe[])
    .filter((recipe) => !saved.has(recipe.name.toLowerCase()))
    .filter((recipe) => diets.every((d) => recipe.tags.map((t) => t.toLowerCase()).includes(d) || !["vegetarian", "vegan", "gluten-free", "dairy-free", "nut-free", "pescatarian"].includes(d)))
    .map((recipe) => {
      const reasons: string[] = [];
      let score = 0;
      const inPantry = recipe.ingredients.filter((i) => pantryKeys.has(ingredientKey(i.name))).length;
      if (inPantry > 0) { score += inPantry * 1.5; reasons.push(`${inPantry} of ${recipe.ingredients.length} ingredients in your pantry`); }
      const tasteHits = recipe.tags.filter((t) => tasteTags.has(t.toLowerCase()));
      if (tasteHits.length) { score += tasteHits.length * 2; reasons.push(`you like ${tasteHits.slice(0, 2).join(" and ")} recipes`); }
      if (recipe.prepMinutes + recipe.cookMinutes <= 30) { score += 0.5; reasons.push("under 30 minutes"); }
      return { recipe, score, reasons };
    })
    .sort((a, b) => b.score - a.score)
    .slice(0, options.limit ?? 6);
}
