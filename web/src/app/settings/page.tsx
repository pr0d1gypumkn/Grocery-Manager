import { revalidatePath } from "next/cache";
import { prisma } from "@/lib/db";
import { money, pageContext } from "@/lib/page";
import { stripeClient } from "@/lib/billing";

export default async function SettingsPage({ searchParams }: { searchParams: Promise<{ upgraded?: string; joined?: string; error?: string }> }) {
  const { user, household, profile, entitlement, has } = await pageContext();
  const params = await searchParams;
  const members = await prisma.householdMember.findMany({ where: { householdId: household.id }, orderBy: { sortOrder: "asc" }, include: { user: true } });
  const stripeReady = Boolean(stripeClient() && process.env.STRIPE_PRICE_MONTHLY && process.env.STRIPE_PRICE_YEARLY);

  async function savePreferences(formData: FormData) {
    "use server";
    const { user } = await pageContext();
    const region = String(formData.get("region")) === "CA" ? "CA" : "US";
    await prisma.user.update({ where: { id: user.id }, data: { region, currency: region === "CA" ? "CAD" : "USD", unitSystem: String(formData.get("unitSystem")) === "metric" ? "metric" : "imperial", dietTags: String(formData.get("dietTags") ?? ""), weeklyBudgetCents: Math.round(Number(formData.get("budget") || 0) * 100) } });
    revalidatePath("/settings");
  }

  async function addMember(formData: FormData) {
    "use server";
    const { household } = await pageContext();
    await prisma.householdMember.create({ data: { householdId: household.id, name: String(formData.get("name")), portionMultiplier: Number(formData.get("portion") || 1), sortOrder: 99 } });
    revalidatePath("/settings");
  }

  async function join(formData: FormData) {
    "use server";
    const { user } = await pageContext();
    const code = String(formData.get("code") ?? "").trim().toUpperCase();
    const target = await prisma.household.findUnique({ where: { inviteCode: code } });
    const { redirect } = await import("next/navigation");
    if (!target) { redirect("/settings?error=No+household+has+that+code"); return; }
    await prisma.householdMember.deleteMany({ where: { userId: user.id, householdId: { not: target.id } } });
    await prisma.householdMember.upsert({ where: { householdId_userId: { householdId: target.id, userId: user.id } }, update: {}, create: { householdId: target.id, userId: user.id, name: user.email?.split("@")[0] ?? "Member" } });
    redirect("/settings?joined=1");
  }

  async function startCheckout(formData: FormData) {
    "use server";
    const { user } = await pageContext();
    const stripe = stripeClient();
    const period = String(formData.get("period")) === "yearly" ? "yearly" : "monthly";
    const price = period === "yearly" ? process.env.STRIPE_PRICE_YEARLY : process.env.STRIPE_PRICE_MONTHLY;
    const { redirect } = await import("next/navigation");
    if (!stripe || !price) { redirect("/settings?error=Stripe+is+not+configured"); return; }
    const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
    let customerId = profile.stripeCustomerId;
    if (!customerId) {
      const customer = await stripe.customers.create({ email: profile.email ?? undefined, metadata: { userId: user.id } });
      customerId = customer.id;
      await prisma.user.update({ where: { id: user.id }, data: { stripeCustomerId: customerId } });
    }
    const origin = process.env.APP_URL ?? "http://localhost:3000";
    const session = await stripe.checkout.sessions.create({ mode: "subscription", customer: customerId, line_items: [{ price, quantity: 1 }], success_url: `${origin}/settings?upgraded=1`, cancel_url: `${origin}/settings`, metadata: { userId: user.id }, subscription_data: { metadata: { userId: user.id } } });
    redirect(session.url ?? "/settings");
  }

  async function demoPlus(formData: FormData) {
    "use server";
    const { user } = await pageContext();
    if (process.env.NODE_ENV === "production") return;
    const enable = String(formData.get("enable")) === "1";
    if (enable) {
      await prisma.subscription.upsert({ where: { providerSubscriptionId: `demo-${user.id}` }, update: { status: "active", currentPeriodEnd: new Date(Date.now() + 30 * 86400 * 1000) }, create: { userId: user.id, provider: "stripe", providerSubscriptionId: `demo-${user.id}`, productId: "demo-monthly", period: "monthly", status: "active", currentPeriodEnd: new Date(Date.now() + 30 * 86400 * 1000) } });
    } else {
      await prisma.subscription.deleteMany({ where: { providerSubscriptionId: `demo-${user.id}` } });
    }
    revalidatePath("/settings");
  }

  return (
    <>
      <h1>Settings</h1>
      {params.upgraded ? <div className="notice">Welcome to Plus. Your subscription will show here once Stripe confirms it.</div> : null}
      {params.joined ? <div className="notice">You joined the household.</div> : null}
      {params.error ? <div className="error">{params.error}</div> : null}

      <h2 id="billing">Plan</h2>
      <div className="card">
        <p style={{ marginTop: 0 }}><strong>{entitlement.tier === "plus" ? "Mealy Plus" : "Free"}</strong>{entitlement.expiresAt ? <span className="muted"> · renews {entitlement.expiresAt.toLocaleDateString()}{entitlement.isInGracePeriod ? " (payment retry)" : ""} via {entitlement.source === "appStore" ? "the App Store" : "Stripe"}</span> : null}</p>
        {entitlement.tier !== "plus" ? (
          <div className="inline" style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
            <form action={startCheckout}><input type="hidden" name="period" value="monthly" /><button type="submit" disabled={!stripeReady}>Plus monthly</button></form>
            <form action={startCheckout}><input type="hidden" name="period" value="yearly" /><button className="primary" type="submit" disabled={!stripeReady}>Plus yearly</button></form>
            {!stripeReady ? <span className="muted">Stripe keys are not configured; on iOS use the App Store.</span> : null}
          </div>
        ) : entitlement.source === "stripe" && profile.stripeCustomerId ? <a className="btn" href="/api/billing/portal">Manage subscription</a> : null}
        {process.env.NODE_ENV !== "production" ? (
          <form action={demoPlus} style={{ marginTop: 10 }}><input type="hidden" name="enable" value={entitlement.tier === "plus" ? "0" : "1"} /><button className="small" type="submit">{entitlement.tier === "plus" ? "Demo: switch back to Free" : "Demo: unlock Plus"}</button></form>
        ) : null}
        <p className="muted" style={{ marginBottom: 0 }}>If a subscription lapses nothing is deleted; only Plus features pause. Export is always available below.</p>
      </div>

      <h2>Region & units</h2>
      <form action={savePreferences} className="card inline">
        <select name="region" defaultValue={profile.region}><option value="US">United States (USD)</option><option value="CA">Canada (CAD)</option></select>
        <select name="unitSystem" defaultValue={profile.unitSystem}><option value="metric">Metric</option><option value="imperial">Imperial</option></select>
        <input name="dietTags" defaultValue={profile.dietTags} placeholder="diet tags: vegetarian, nut-free" />
        <label className="muted">Weekly budget <input name="budget" type="number" min={0} step={5} defaultValue={profile.weeklyBudgetCents / 100} style={{ width: 90 }} /></label>
        <button className="primary" type="submit">Save</button>
        {!has("price_aware_shopping") ? <span className="muted">Budget mode needs Plus.</span> : <span className="muted">Current: {money(profile.weeklyBudgetCents, profile.currency)}</span>}
      </form>

      <h2>Household</h2>
      <div className="card">
        <p style={{ marginTop: 0 }}><strong>{household.name}</strong> · owner {household.ownerId === user.id ? "you" : "someone else"}</p>
        {members.map((m) => <div key={m.id} className="row"><span className="grow">{m.name}{m.user ? <span className="muted"> · {m.user.email}</span> : null}</span><span className="muted">{m.portionMultiplier}× portions</span></div>)}
        <form action={addMember} className="inline" style={{ marginTop: 8 }}>
          <input name="name" placeholder="Add a person" required />
          <input name="portion" type="number" min={0.25} max={3} step={0.25} defaultValue={1} style={{ width: 80 }} />
          <button type="submit">Add</button>
        </form>
        {has("household_sharing") ? (
          <p className="muted" style={{ marginBottom: 0 }}>Invite code: <strong>{household.inviteCode}</strong>. Anyone who signs in and enters it joins this household; they don't need their own Plus.</p>
        ) : (
          <p className="muted" style={{ marginBottom: 0 }}>Real-time sharing with other accounts needs Plus. Portion sizes work on the free plan.</p>
        )}
        <form action={join} className="inline" style={{ marginTop: 8 }}>
          <input name="code" placeholder="Join with an invite code" />
          <button type="submit">Join</button>
        </form>
      </div>

      <h2>Your data</h2>
      <div className="card inline" style={{ display: "flex", gap: 8 }}>
        <a className="btn" href="/api/export">Download everything (JSON)</a>
        <span className="muted">Same format as the iOS export, so it imports there too.</span>
      </div>
    </>
  );
}
