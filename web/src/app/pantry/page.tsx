import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db";
import { pageContext } from "@/lib/page";
import { display, formatQuantity } from "@/lib/units";

export default async function PantryPage() {
  const { household, profile } = await pageContext();
  const [items, locations] = await Promise.all([
    prisma.pantryItem.findMany({ where: { householdId: household.id, deletedAt: null }, include: { location: true }, orderBy: { expiryDate: "asc" } }),
    prisma.pantryLocation.findMany({ where: { householdId: household.id } }),
  ]);
  const now = Date.now();
  const soon = now + 3 * 86400 * 1000;
  const system = profile.unitSystem as "metric" | "imperial";

  async function add(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    await prisma.pantryItem.create({ data: { householdId: household.id, name: String(formData.get("name")), quantity: Number(formData.get("quantity") || 1), initialQuantity: Number(formData.get("quantity") || 1), unit: String(formData.get("unit") || "item"), category: String(formData.get("category") || "Other"), expiryDate: new Date(String(formData.get("expiry"))), locationId: String(formData.get("locationId")) || null } });
    revalidatePath("/pantry");
  }

  async function remove(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    await prisma.pantryItem.updateMany({ where: { id: String(formData.get("id")), householdId: household.id }, data: { deletedAt: new Date() } });
    revalidatePath("/pantry");
  }

  const groups = locations.map((l) => ({ location: l, items: items.filter((i) => i.locationId === l.id) }));
  const unassigned = items.filter((i) => !i.locationId);

  return (
    <>
      <h1>Pantry</h1>
      <p className="lede">{items.length} items · {items.filter((i) => i.expiryDate.getTime() <= soon && i.expiryDate.getTime() >= now).length} expiring within 3 days</p>
      {[...groups, { location: { id: "none", name: "Unassigned" }, items: unassigned }].filter((g) => g.items.length).map((group) => (
        <div key={group.location.id} className="card" style={{ marginBottom: 12 }}>
          <h2 style={{ marginTop: 0 }}>{group.location.name}</h2>
          {group.items.map((item) => {
            const shown = display(item.quantity, item.unit, system);
            const state = item.expiryDate.getTime() < now ? "expired" : item.expiryDate.getTime() <= soon ? "soon" : "fresh";
            return (
              <div key={item.id} className="row">
                <span className="grow">{item.name} <span className="muted">{formatQuantity(shown.quantity)} {shown.unit}</span>{item.source === "prep" ? <span className="badge green" style={{ marginLeft: 6 }}>prepped</span> : null}</span>
                <span className={`badge ${state === "fresh" ? "green" : "orange"}`}>{state === "expired" ? "Expired" : state === "soon" ? "Use soon" : item.expiryDate.toLocaleDateString(undefined, { month: "short", day: "numeric" })}</span>
                <form action={remove}><input type="hidden" name="id" value={item.id} /><button className="ghost small" type="submit">Remove</button></form>
              </div>
            );
          })}
        </div>
      ))}
      <h2>Add stock</h2>
      <form action={add} className="card inline">
        <input name="name" placeholder="Item" required />
        <input name="quantity" type="number" step="0.25" min={0} defaultValue={1} style={{ width: 90 }} />
        <input name="unit" defaultValue="item" style={{ width: 80 }} />
        <select name="category">{["Produce", "Bakery", "Meat", "Seafood", "Dairy", "Pantry", "Beverages", "Frozen", "Other"].map((c) => <option key={c}>{c}</option>)}</select>
        <input name="expiry" type="date" defaultValue={new Date(now + 7 * 86400 * 1000).toISOString().slice(0, 10)} />
        <select name="locationId"><option value="">Unassigned</option>{locations.map((l) => <option key={l.id} value={l.id}>{l.name}</option>)}</select>
        <button className="primary" type="submit">Add</button>
      </form>
    </>
  );
}
