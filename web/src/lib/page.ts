import { redirect } from "next/navigation";
import { currentUser, householdFor } from "./auth";
import { entitlementFor, entitlementHasFeature, type Entitlement, type Feature } from "./entitlements";
import { prisma } from "./db";

/** Everything a page needs: the user, their household, profile and entitlement. */
export async function pageContext() {
  const user = await currentUser();
  if (!user) redirect("/login");
  const [household, profile, entitlement] = await Promise.all([householdFor(user.id), prisma.user.findUniqueOrThrow({ where: { id: user.id } }), entitlementFor(user.id)]);
  const has = (feature: Feature) => entitlementHasFeature(entitlement, feature);
  return { user, household, profile, entitlement: entitlement as Entitlement, has };
}

export function money(cents: number, currency: string) {
  return new Intl.NumberFormat(currency === "CAD" ? "en-CA" : "en-US", { style: "currency", currency }).format(cents / 100);
}

export function weekStartOf(date = new Date()): Date {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7));
  return d;
}

export function addDays(date: Date, days: number): Date {
  const d = new Date(date);
  d.setUTCDate(d.getUTCDate() + days);
  return d;
}
