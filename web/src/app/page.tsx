import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db";
import { addDays, money, pageContext, weekStartOf } from "@/lib/page";
import { shortfalls } from "@/lib/ingredients";
import { priceList } from "@/lib/prices/registry";
import { Locked } from "@/components/Locked";
import { planWeek } from "@/lib/planner";
import { bestQuotes } from "@/lib/prices/registry";
import { ingredientKey } from "@/lib/ingredients";

const MEALS = ["Breakfast", "Lunch", "Dinner", "Snack"];

export default async function PlanPage({ searchParams }: { searchParams: Promise<{ week?: string; planned?: string }> }) {
  const { household, profile, has } = await pageContext();
  const params = await searchParams;
  const weekStart = params.week ? weekStartOf(new Date(params.week)) : weekStartOf();
  const weekEnd = addDays(weekStart, 7);

  const [meals, recipes, pantry] = await Promise.all([
    prisma.mealPlanEntry.findMany({ where: { householdId: household.id, deletedAt: null, date: { gte: weekStart, lt: weekEnd } }, include: { recipe: { include: { ingredients: true } } }, orderBy: { date: "asc" } }),
    prisma.recipe.findMany({ where: { householdId: household.id, deletedAt: null }, orderBy: { name: "asc" }, include: { ingredients: true } }),
    prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null } }),
  ]);

  const requirements = meals.filter((m) => !m.isCooked && m.recipe && !m.batchId).flatMap((m) => m.recipe!.ingredients.map((i) => ({ name: i.name, quantity: i.quantity * (m.recipe!.servings > 0 ? m.servings / m.recipe!.servings : 1), unit: i.unit })));
  const missing = shortfalls(requirements, pantry.map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, expiryDate: p.expiryDate })));
  const priced = has("price_aware_shopping") && missing.length ? await priceList(profile.region as "US" | "CA", missing.map((m) => ({ name: m.name, quantity: m.missing, unit: m.unit }))) : null;

  async function addMeal(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    const date = new Date(String(formData.get("date")));
    await prisma.mealPlanEntry.create({ data: { householdId: household.id, date: new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate())), mealType: String(formData.get("mealType")), recipeId: String(formData.get("recipeId")), servings: Number(formData.get("servings") || 2) } });
    revalidatePath("/");
  }

  async function toggleCooked(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    const id = String(formData.get("id"));
    const entry = await prisma.mealPlanEntry.findFirst({ where: { id, householdId: household.id } });
    if (entry) await prisma.mealPlanEntry.update({ where: { id }, data: { isCooked: !entry.isCooked } });
    revalidatePath("/");
  }

  async function removeMeal(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    await prisma.mealPlanEntry.updateMany({ where: { id: String(formData.get("id")), householdId: household.id }, data: { deletedAt: new Date() } });
    revalidatePath("/");
  }

  async function autoPlan(formData: FormData) {
    "use server";
    const { household, profile, has } = await pageContext();
    if (!has("automatic_planning")) return;
    const weekStart = weekStartOf(new Date(String(formData.get("week"))));
    const rows = await prisma.recipe.findMany({ where: { householdId: household.id, deletedAt: null }, include: { ingredients: true } });
    const pantryRows = await prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null } });
    const members = await prisma.householdMember.findMany({ where: { householdId: household.id } });
    const existing = await prisma.mealPlanEntry.findMany({ where: { householdId: household.id, deletedAt: null, date: { gte: weekStart, lt: addDays(weekStart, 7) } } });
    const plannerRecipes = rows.map((r) => ({ id: r.id, name: r.name, servings: r.servings, tags: r.tags.split(",").map((t) => t.trim()).filter(Boolean), totalMinutes: r.prepMinutes + r.cookMinutes, ingredients: r.ingredients.map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit })) }));
    const quotes = await bestQuotes(profile.region as "US" | "CA", [...new Map(plannerRecipes.flatMap((r) => r.ingredients).map((i) => [ingredientKey(i.name), i])).values()]);
    const plan = planWeek(plannerRecipes, {
      weekStart,
      slots: [0, 1, 2, 3, 4, 5, 6].flatMap((d) => [{ dayOffset: d, mealType: "Dinner" as const }, ...(d < 5 ? [{ dayOffset: d, mealType: "Lunch" as const, maxMinutes: 20 }] : [])]),
      servingsPerMeal: Math.max(members.reduce((s, m) => s + m.portionMultiplier, 0), 2),
      dietTags: profile.dietTags.split(",").map((t) => t.trim()).filter(Boolean),
      pantry: pantryRows.map((p) => ({ name: p.name, quantity: p.quantity, unit: p.unit, expiryDate: p.expiryDate })),
      priceCentsByKey: new Map([...quotes.entries()].map(([k, q]) => [k, q.priceCents])),
      weeklyBudgetCents: profile.weeklyBudgetCents,
      locked: existing.filter((e) => e.recipeId).map((e) => ({ recipeId: e.recipeId!, dayOffset: Math.round((e.date.getTime() - weekStart.getTime()) / 86400000), mealType: e.mealType })),
    });
    for (const slot of plan) {
      await prisma.mealPlanEntry.create({ data: { householdId: household.id, date: addDays(weekStart, slot.dayOffset), mealType: slot.mealType, recipeId: slot.recipeId, servings: slot.servings, note: slot.reasons.slice(0, 2).join("; ") } });
    }
    revalidatePath("/");
  }

  const days = [0, 1, 2, 3, 4, 5, 6].map((offset) => addDays(weekStart, offset));
  const todayKey = new Date().toISOString().slice(0, 10);
  const cooked = meals.filter((m) => m.isCooked).length;

  return (
    <>
      <h1>Week of {weekStart.toLocaleDateString(undefined, { month: "long", day: "numeric", timeZone: "UTC" })}</h1>
      <p className="lede">
        <a href={`/?week=${addDays(weekStart, -7).toISOString().slice(0, 10)}`}>← Previous</a> · <a href="/">This week</a> · <a href={`/?week=${addDays(weekStart, 7).toISOString().slice(0, 10)}`}>Next →</a>
      </p>

      <div className="grid cols-3">
        <div className="card stat"><span className="value">{meals.length}</span><span className="label">Meals planned</span></div>
        <div className="card stat"><span className="value">{cooked}</span><span className="label">Cooked</span></div>
        <div className="card stat"><span className="value">{missing.length}</span><span className="label">Items to buy{priced ? ` · about ${money(priced.totalCents, priced.currency)}` : ""}</span></div>
      </div>

      <h2>Calendar</h2>
      <div className="grid cols-7">
        {days.map((day) => {
          const key = day.toISOString().slice(0, 10);
          const dayMeals = meals.filter((m) => m.date.toISOString().slice(0, 10) === key);
          return (
            <div key={key} className={`day ${key === todayKey ? "today" : ""}`}>
              <h3>{day.toLocaleDateString(undefined, { weekday: "short", day: "numeric", timeZone: "UTC" })}</h3>
              {dayMeals.map((meal) => (
                <div key={meal.id} className="meal">
                  <div className="type">{meal.mealType}{meal.batchId ? " · leftovers" : ""}</div>
                  <div className={meal.isCooked ? "checked" : ""}>{meal.recipe?.name ?? "Deleted recipe"} <span className="muted">×{meal.servings}</span></div>
                  <div style={{ display: "flex", gap: 4, marginTop: 4 }}>
                    <form action={toggleCooked}><input type="hidden" name="id" value={meal.id} /><button className="ghost small" type="submit">{meal.isCooked ? "Undo" : "Cooked"}</button></form>
                    <form action={removeMeal}><input type="hidden" name="id" value={meal.id} /><button className="ghost small" type="submit">Remove</button></form>
                  </div>
                </div>
              ))}
            </div>
          );
        })}
      </div>

      <h2>Add a meal</h2>
      <form action={addMeal} className="card inline">
        <input type="date" name="date" defaultValue={todayKey} required />
        <select name="mealType">{MEALS.map((m) => <option key={m}>{m}</option>)}</select>
        <select name="recipeId" required>
          {recipes.map((r) => <option key={r.id} value={r.id}>{r.name}</option>)}
        </select>
        <input type="number" name="servings" min={1} max={24} defaultValue={2} style={{ width: 80 }} />
        <button className="primary" type="submit">Add</button>
        {recipes.length === 0 ? <span className="muted">Add a recipe first.</span> : null}
      </form>

      <h2>Plan it for me</h2>
      {has("automatic_planning") ? (
        <form action={autoPlan} className="card inline">
          <input type="hidden" name="week" value={weekStart.toISOString().slice(0, 10)} />
          <span>Fills the empty dinners and weekday lunches from your recipes, pantry, diet and budget. Existing meals are kept.</span>
          <button className="primary" type="submit">Build this week</button>
        </form>
      ) : <Locked feature="automatic_planning" />}

      {missing.length > 0 ? (
        <>
          <h2>Missing for this week</h2>
          <div className="card">
            {missing.map((line) => {
              const quote = priced?.lines.find((l) => l.name === line.name)?.quote;
              return (
                <div key={line.name} className="row">
                  <span className="grow">{line.name}</span>
                  <span className="muted">{line.missing.toFixed(2).replace(/\.?0+$/, "")} {line.unit}</span>
                  {quote ? <span className="badge accent">{money(quote.priceCents, quote.currency)}{quote.isSale ? " sale" : ""}</span> : null}
                </div>
              );
            })}
            <p className="muted" style={{ marginBottom: 0 }}>These are on your <a href="/groceries">grocery list</a>.</p>
          </div>
        </>
      ) : null}
    </>
  );
}
