import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db";
import { pageContext } from "@/lib/page";
import { suggest } from "@/lib/suggestions";
import { Locked } from "@/components/Locked";

export default async function RecipesPage() {
  const { household, profile, has } = await pageContext();
  const [recipes, pantry] = await Promise.all([
    prisma.recipe.findMany({ where: { householdId: household.id, deletedAt: null }, orderBy: { name: "asc" }, include: { ingredients: true } }),
    prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null } }),
  ]);
  const suggestions = has("recipe_suggestions")
    ? suggest({ savedNames: recipes.map((r) => r.name), savedTags: recipes.flatMap((r) => r.tags.split(",").map((t) => t.trim()).filter(Boolean)), pantry: pantry.map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, expiryDate: p.expiryDate })), dietTags: profile.dietTags.split(",").map((t) => t.trim()).filter(Boolean), limit: 4 })
    : [];

  async function createRecipe(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    const lines = String(formData.get("ingredients") ?? "").split("\n").map((l) => l.trim()).filter(Boolean);
    await prisma.recipe.create({
      data: {
        householdId: household.id,
        name: String(formData.get("name")),
        servings: Number(formData.get("servings") || 2),
        instructions: String(formData.get("instructions") ?? ""),
        tags: String(formData.get("tags") ?? ""),
        ingredients: { create: lines.map((line, sortOrder) => parseLine(line, sortOrder)) },
      },
    });
    revalidatePath("/recipes");
  }

  async function saveSuggestion(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    const payload = JSON.parse(String(formData.get("recipe")));
    await prisma.recipe.create({ data: { householdId: household.id, name: payload.name, servings: payload.servings, prepMinutes: payload.prepMinutes, cookMinutes: payload.cookMinutes, tags: payload.tags.join(", "), instructions: payload.instructions.map((s: string, i: number) => `${i + 1}. ${s}`).join("\n"), ingredients: { create: payload.ingredients.map((i: { name: string; quantity: number; unit: string }, sortOrder: number) => ({ ...i, sortOrder })) } } });
    revalidatePath("/recipes");
  }

  return (
    <>
      <h1>Recipes</h1>
      <p className="lede">{recipes.length} saved. Import from any recipe site in the iOS app; here you can add them by hand.</p>
      <div className="card">
        {recipes.map((recipe) => (
          <div key={recipe.id} className="row">
            <div className="grow">
              <a href={`/recipes/${recipe.id}`}><strong>{recipe.name}</strong></a>
              <div className="muted">{recipe.ingredients.length} ingredients · serves {recipe.servings}{recipe.prepMinutes + recipe.cookMinutes ? ` · ${recipe.prepMinutes + recipe.cookMinutes} min` : ""}{recipe.tags ? ` · ${recipe.tags}` : ""}</div>
            </div>
          </div>
        ))}
        {recipes.length === 0 ? <p className="muted">No recipes yet.</p> : null}
      </div>

      <h2>Ideas for you</h2>
      {has("recipe_suggestions") ? (
        <div className="grid cols-3">
          {suggestions.map(({ recipe, reasons }) => (
            <div key={recipe.id} className="card">
              <strong>{recipe.name}</strong>
              <div className="muted">{recipe.tags.join(", ")} · {recipe.prepMinutes + recipe.cookMinutes} min</div>
              <div className="muted" style={{ margin: "6px 0" }}>{reasons.join(" · ") || "New to your collection"}</div>
              <form action={saveSuggestion}><input type="hidden" name="recipe" value={JSON.stringify(recipe)} /><button className="small" type="submit">Save recipe</button></form>
            </div>
          ))}
        </div>
      ) : <Locked feature="recipe_suggestions" />}

      <h2>New recipe</h2>
      <form action={createRecipe} className="card grid">
        <input name="name" placeholder="Name" required />
        <div className="inline" style={{ display: "flex", gap: 8 }}>
          <input name="servings" type="number" min={1} defaultValue={2} style={{ width: 90 }} />
          <input name="tags" placeholder="tags, comma separated" style={{ flex: 1 }} />
        </div>
        <textarea name="ingredients" rows={5} placeholder={"One ingredient per line, e.g.\n2 cups rice\n400 g chicken thighs"} />
        <textarea name="instructions" rows={5} placeholder="One step per line" />
        <button className="primary" type="submit">Save</button>
      </form>
    </>
  );
}

/** Tiny ingredient line parser for the web form ("2 cups rice"). The iOS app has the full one. */
function parseLine(line: string, sortOrder: number) {
  const match = line.match(/^(\d+(?:[.,/]\d+)?)\s*([a-zA-Z]+)?\s+(.+)$/);
  if (!match) return { name: line, quantity: 1, unit: "item", sortOrder };
  const quantity = match[1].includes("/") ? Number(match[1].split("/")[0]) / Number(match[1].split("/")[1]) : Number(match[1].replace(",", "."));
  const unitMap: Record<string, string> = { g: "g", gram: "g", grams: "g", kg: "kg", ml: "ml", l: "L", cup: "cup", cups: "cup", tbsp: "tbsp", tsp: "tsp", oz: "oz", lb: "lb", lbs: "lb", item: "item", items: "item" };
  const unit = match[2] ? unitMap[match[2].toLowerCase()] : undefined;
  return { name: unit ? match[3] : `${match[2] ?? ""} ${match[3]}`.trim(), quantity, unit: unit ?? "item", sortOrder };
}
