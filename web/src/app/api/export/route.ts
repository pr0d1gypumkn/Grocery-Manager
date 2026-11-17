import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { householdFor } from "@/lib/auth";
import { pullBundle } from "@/lib/sync";

/** Full export of the household's data. Never gated: users are never locked in. */
export const GET = withUser(async (_request, user) => {
  const household = await householdFor(user.id);
  const bundle = await pullBundle(household.id);
  return new NextResponse(JSON.stringify(bundle, null, 2), {
    headers: { "Content-Type": "application/json", "Content-Disposition": 'attachment; filename="mealy-export.json"' },
  });
});
