import { notFound } from "next/navigation";
import { prisma } from "@/lib/db";
import { pageContext } from "@/lib/page";
import { display, formatQuantity } from "@/lib/units";

export default async function RecipePage({ params }: { params: Promise<{ id: string }> }) {
  const { household, profile } = await pageContext();
  const { id } = await params;
  const recipe = await prisma.recipe.findFirst({ where: { id, householdId: household.id, deletedAt: null }, include: { ingredients: { orderBy: { sortOrder: "asc" } } } });
  if (!recipe) notFound();
  const steps = recipe.instructions.split("\n").map((s) => s.replace(/^\s*\d+[.)]\s*/, "").trim()).filter(Boolean);
  const system = profile.unitSystem as "metric" | "imperial";
  return (
    <>
      <h1>{recipe.name}</h1>
      <p className="lede">Serves {recipe.servings}{recipe.prepMinutes ? ` · ${recipe.prepMinutes} min prep` : ""}{recipe.cookMinutes ? ` · ${recipe.cookMinutes} min cook` : ""}{recipe.tags ? ` · ${recipe.tags}` : ""}{recipe.sourceUrl ? <> · <a href={recipe.sourceUrl}>source</a></> : null}</p>
      {recipe.caloriesPerServing ? <div className="card" style={{ marginBottom: 12 }}><strong>{Math.round(recipe.caloriesPerServing)} kcal</strong> per serving · P {Math.round(recipe.proteinPerServing)}g · C {Math.round(recipe.carbsPerServing)}g · F {Math.round(recipe.fatPerServing)}g</div> : null}
      <div className="grid cols-3" style={{ gridTemplateColumns: "1fr 2fr" }}>
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Ingredients</h2>
          {recipe.ingredients.map((i) => {
            const shown = display(i.quantity, i.unit, system);
            return <div key={i.id} className="row"><span className="grow">{i.name}{i.note ? <span className="muted"> · {i.note}</span> : null}</span><span className="muted">{formatQuantity(shown.quantity)} {shown.unit}</span></div>;
          })}
        </div>
        <div className="card">
          <h2 style={{ marginTop: 0 }}>Steps</h2>
          {steps.map((step, index) => <div key={index} className="step"><span className="n">{index + 1}</span><span>{step}</span></div>)}
          {steps.length === 0 ? <p className="muted">No instructions.</p> : null}
        </div>
      </div>
    </>
  );
}
