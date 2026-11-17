import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { bundleSchema, pullBundle, pushBundle } from "@/lib/sync";

/** Pull the shared household. Plus only: free users keep everything on-device. */
export const GET = withUser(async (_request, user) => {
  const household = await householdFor(user.id);
  return NextResponse.json({ householdId: household.id, bundle: await pullBundle(household.id) });
}, "household_sharing");

/** Push local changes (ExportBundle shape). */
export const POST = withUser(async (request, user) => {
  const parsed = bundleSchema.safeParse(await request.json().catch(() => ({})));
  if (!parsed.success) return NextResponse.json({ error: "Invalid bundle", issues: parsed.error.issues.slice(0, 5) }, { status: 400 });
  const household = await householdFor(user.id);
  const counts = await pushBundle(household.id, parsed.data);
  return NextResponse.json({ householdId: household.id, counts, bundle: await pullBundle(household.id) });
}, "household_sharing");
