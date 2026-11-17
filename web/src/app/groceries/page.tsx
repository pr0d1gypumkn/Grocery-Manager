import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db";
import { money, pageContext } from "@/lib/page";
import { aisleIndex } from "@/lib/ingredients";
import { display, formatQuantity } from "@/lib/units";
import { checkoutProvidersFor, priceList } from "@/lib/prices/registry";
import { Locked } from "@/components/Locked";

export default async function GroceriesPage() {
  const { household, profile, has } = await pageContext();
  const items = await prisma.groceryItem.findMany({ where: { householdId: household.id, deletedAt: null } });
  const sorted = [...items].sort((a, b) => aisleIndex(a.category) - aisleIndex(b.category) || Number(a.isChecked) - Number(b.isChecked) || a.name.localeCompare(b.name));
  const region = profile.region as "US" | "CA";
  const pending = sorted.filter((i) => !i.isChecked);
  const priced = has("price_aware_shopping") && pending.length ? await priceList(region, pending.map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit }))) : null;
  const providers = has("checkout_links") ? checkoutProvidersFor(region) : [];
  const system = profile.unitSystem as "metric" | "imperial";

  async function toggle(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    const id = String(formData.get("id"));
    const item = await prisma.groceryItem.findFirst({ where: { id, householdId: household.id } });
    if (!item) return;
    await prisma.groceryItem.update({ where: { id }, data: { isChecked: !item.isChecked, checkedAt: item.isChecked ? null : new Date() } });
    if (!item.isChecked) {
      // Checked off → straight into stock, same as the app.
      const locations = await prisma.pantryLocation.findMany({ where: { householdId: household.id } });
      const wanted = ["Produce", "Dairy", "Meat", "Seafood", "Beverages"].includes(item.category) ? "fridge" : item.category === "Frozen" ? "freezer" : "pantry";
      const location = locations.find((l) => l.name.toLowerCase().includes(wanted)) ?? locations[0];
      const days: Record<string, number> = { Produce: 7, Dairy: 10, Meat: 3, Seafood: 3, Bakery: 5, Frozen: 90, Beverages: 30, Pantry: 180 };
      await prisma.pantryItem.create({ data: { householdId: household.id, name: item.name, quantity: item.quantity, unit: item.unit, initialQuantity: item.quantity, category: item.category, locationId: location?.id, source: "grocery", expiryDate: new Date(Date.now() + (days[item.category] ?? 30) * 86400 * 1000) } });
    }
    revalidatePath("/groceries");
  }

  async function add(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    await prisma.groceryItem.create({ data: { householdId: household.id, name: String(formData.get("name")), quantity: Number(formData.get("quantity") || 1), unit: String(formData.get("unit") || "item"), category: String(formData.get("category") || "Other") } });
    revalidatePath("/groceries");
  }

  async function clearChecked() {
    "use server";
    const { household } = await pageContext();
    await prisma.groceryItem.updateMany({ where: { householdId: household.id, isChecked: true }, data: { deletedAt: new Date() } });
    revalidatePath("/groceries");
  }

  async function checkout(formData: FormData) {
    "use server";
    const { household, profile, has } = await pageContext();
    if (!has("checkout_links")) return;
    const provider = checkoutProvidersFor(profile.region as "US" | "CA").find((p) => p.key === String(formData.get("provider")));
    const lines = (await prisma.groceryItem.findMany({ where: { householdId: household.id, deletedAt: null, isChecked: false } })).map((i) => ({ name: i.name, quantity: i.quantity, unit: i.unit }));
    if (!provider?.checkoutURL) return;
    const { redirect } = await import("next/navigation");
    redirect(await provider.checkoutURL(lines));
  }

  const budget = profile.weeklyBudgetCents;
  return (
    <>
      <h1>Groceries</h1>
      <p className="lede">Sorted by aisle. Checking an item off puts it into the pantry.</p>
      <div className="grid cols-3">
        <div className="card stat"><span className="value">{pending.length}</span><span className="label">To buy</span></div>
        <div className="card stat"><span className="value">{items.length - pending.length}</span><span className="label">In basket</span></div>
        {priced ? <div className="card stat"><span className="value">{money(priced.totalCents, priced.currency)}</span><span className="label">Estimate{budget ? ` · budget ${money(budget, priced.currency)}` : ""}{budget && priced.totalCents > budget ? <span className="badge orange" style={{ marginLeft: 6 }}>over</span> : null}</span></div> : null}
      </div>
      {!has("price_aware_shopping") ? <div style={{ marginTop: 12 }}><Locked feature="price_aware_shopping" /></div> : null}

      <div className="card" style={{ marginTop: 16 }}>
        {sorted.map((item) => {
          const shown = display(item.quantity, item.unit, system);
          const quote = priced?.lines.find((l) => l.name === item.name)?.quote;
          return (
            <div key={item.id} className="row">
              <form action={toggle}><input type="hidden" name="id" value={item.id} /><button className="small" type="submit">{item.isChecked ? "✓" : "○"}</button></form>
              <span className={`grow ${item.isChecked ? "checked" : ""}`}>{item.name} <span className="muted">{formatQuantity(shown.quantity)} {shown.unit}</span></span>
              <span className="badge accent">{item.category}</span>
              {item.source === "plan" ? <span className="badge green">plan</span> : null}
              {quote ? <span className="muted">{money(quote.priceCents, quote.currency)}{quote.isSale ? " · sale" : ""}</span> : null}
            </div>
          );
        })}
        {items.length === 0 ? <p className="muted">Nothing to buy.</p> : null}
      </div>
      {items.length - pending.length > 0 ? <form action={clearChecked} style={{ marginTop: 10 }}><button type="submit">Clear bought items</button></form> : null}

      <h2>Add item</h2>
      <form action={add} className="card inline">
        <input name="name" placeholder="Item" required />
        <input name="quantity" type="number" step="0.25" min={0} defaultValue={1} style={{ width: 90 }} />
        <input name="unit" defaultValue="item" style={{ width: 80 }} />
        <select name="category">{["Produce", "Bakery", "Meat", "Seafood", "Dairy", "Pantry", "Beverages", "Frozen", "Other"].map((c) => <option key={c}>{c}</option>)}</select>
        <button className="primary" type="submit">Add</button>
      </form>

      <h2>Checkout</h2>
      {has("checkout_links") ? (
        <div className="card inline" style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {providers.map((p) => <form key={p.key} action={checkout}><input type="hidden" name="provider" value={p.key} /><button type="submit">Send to {p.name}</button></form>)}
          <span className="muted">Opens the retailer with your unchecked items. Full cart hand-off needs each retailer's API key.</span>
        </div>
      ) : <Locked feature="checkout_links" />}
    </>
  );
}
