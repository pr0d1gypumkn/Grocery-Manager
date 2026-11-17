import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { entitlementFor, entitlementHasFeature, FEATURES, type Feature } from "@/lib/entitlements";

/** The app's single source of truth once signed in. Mirrors EntitlementSnapshot on iOS. */
export const GET = withUser(async (_request, user) => {
  const entitlement = await entitlementFor(user.id);
  const features = Object.fromEntries((Object.keys(FEATURES) as Feature[]).map((f) => [f, entitlementHasFeature(entitlement, f)]));
  return NextResponse.json({
    tier: entitlement.tier,
    expiresAt: entitlement.expiresAt,
    source: entitlement.source,
    isInGracePeriod: entitlement.isInGracePeriod,
    productId: entitlement.productId,
    features,
  });
});
