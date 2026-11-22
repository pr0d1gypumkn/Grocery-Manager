// The single server-side definition of what each feature needs and whether a user has it.
// `hasFeature(userId, "price_aware_shopping")` is the only call API routes should make.

import { prisma } from "./db";

export const FEATURES = {
  price_aware_shopping: { tier: "plus", title: "Price-aware shopping" },
  automatic_planning: { tier: "plus", title: "Automatic planning" },
  recipe_suggestions: { tier: "plus", title: "New recipe ideas" },
  social_import: { tier: "plus", title: "Social & photo import" },
  household_sharing: { tier: "plus", title: "Household sharing" },
  checkout_links: { tier: "plus", title: "Grocery checkout" },
} as const;

export type Feature = keyof typeof FEATURES;
export type Tier = "free" | "plus";

const TIER_RANK: Record<Tier, number> = { free: 0, plus: 1 };

export interface SubscriptionLike {
  tier: string;
  status: string;
  currentPeriodEnd: Date;
  isInGracePeriod: boolean;
  provider?: string;
  productId?: string;
}

export interface Entitlement {
  tier: Tier;
  expiresAt: Date | null;
  source: "none" | "appStore" | "stripe" | "server";
  isInGracePeriod: boolean;
  productId: string;
}

export const FREE: Entitlement = { tier: "free", expiresAt: null, source: "none", isInGracePeriod: false, productId: "" };

function isActive(subscription: SubscriptionLike, now: Date): boolean {
  if (["revoked", "cancelled_immediately"].includes(subscription.status)) return false;
  if (subscription.currentPeriodEnd >= now) return true;
  return subscription.isInGracePeriod || subscription.status === "grace";
}

/** Reduces every subscription row a user has to one answer. A lapsed subscription is just "free". */
export function resolveEntitlement(subscriptions: SubscriptionLike[], now = new Date()): Entitlement {
  const active = subscriptions.filter((s) => isActive(s, now) && (TIER_RANK[s.tier as Tier] ?? 0) > 0);
  if (active.length === 0) return FREE;
  const best = active.sort((a, b) => {
    const tierDelta = (TIER_RANK[b.tier as Tier] ?? 0) - (TIER_RANK[a.tier as Tier] ?? 0);
    return tierDelta !== 0 ? tierDelta : b.currentPeriodEnd.getTime() - a.currentPeriodEnd.getTime();
  })[0];
  return {
    tier: best.tier as Tier,
    expiresAt: best.currentPeriodEnd,
    source: best.provider === "apple" ? "appStore" : best.provider === "stripe" ? "stripe" : "server",
    isInGracePeriod: best.isInGracePeriod || best.status === "grace",
    productId: best.productId ?? "",
  };
}

export function entitlementHasFeature(entitlement: Entitlement, feature: Feature, now = new Date()): boolean {
  const needed = FEATURES[feature].tier as Tier;
  if (TIER_RANK[entitlement.tier] < TIER_RANK[needed]) return false;
  if (entitlement.tier === "free") return false;
  if (entitlement.expiresAt && entitlement.expiresAt < now && !entitlement.isInGracePeriod) return false;
  return true;
}

export async function entitlementFor(userId: string): Promise<Entitlement> {
  const subscriptions = await prisma.subscription.findMany({ where: { userId } });
  return resolveEntitlement(subscriptions);
}

export async function hasFeature(userId: string, feature: Feature): Promise<boolean> {
  if (entitlementHasFeature(await entitlementFor(userId), feature)) return true;
  // Members of someone else's household share through the owner's plan; they don't need
  // Plus themselves. This covers sharing only, not the owner's other Plus features.
  if (feature === "household_sharing") {
    const membership = await prisma.householdMember.findFirst({
      where: { userId, household: { ownerId: { not: userId } } },
      select: { household: { select: { ownerId: true } } },
    });
    if (membership) return entitlementHasFeature(await entitlementFor(membership.household.ownerId), feature);
  }
  return false;
}

export class FeatureLockedError extends Error {
  constructor(public feature: Feature) {
    super(`${FEATURES[feature].title} requires Mealy Plus`);
  }
}

/** Throws when the feature is off; API routes turn that into a 402 with an upgrade hint. */
export async function requireFeature(userId: string, feature: Feature): Promise<void> {
  if (!(await hasFeature(userId, feature))) throw new FeatureLockedError(feature);
}
