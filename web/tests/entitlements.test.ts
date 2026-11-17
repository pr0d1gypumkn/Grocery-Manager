import { describe, expect, it } from "vitest";
import { entitlementHasFeature, FEATURES, FREE, resolveEntitlement, type Feature } from "@/lib/entitlements";

const now = new Date();
const days = (n: number) => new Date(now.getTime() + n * 86400 * 1000);
const sub = (over: Partial<{ tier: string; status: string; currentPeriodEnd: Date; isInGracePeriod: boolean; provider: string }>) => ({
  tier: "plus", status: "active", currentPeriodEnd: days(30), isInGracePeriod: false, provider: "stripe", productId: "x", ...over,
});

describe("entitlements", () => {
  it("free has nothing", () => {
    for (const feature of Object.keys(FEATURES) as Feature[]) expect(entitlementHasFeature(FREE, feature, now)).toBe(false);
  });
  it("active plus unlocks every feature", () => {
    const entitlement = resolveEntitlement([sub({})], now);
    for (const feature of Object.keys(FEATURES) as Feature[]) expect(entitlementHasFeature(entitlement, feature, now)).toBe(true);
  });
  it("lapsed subscriptions resolve to free", () => {
    expect(resolveEntitlement([sub({ currentPeriodEnd: days(-1), status: "expired" })], now).tier).toBe("free");
    expect(resolveEntitlement([sub({ status: "revoked" })], now).tier).toBe("free");
  });
  it("grace period keeps access", () => {
    const entitlement = resolveEntitlement([sub({ currentPeriodEnd: days(-1), status: "grace", isInGracePeriod: true })], now);
    expect(entitlement.tier).toBe("plus");
    expect(entitlementHasFeature(entitlement, "household_sharing", now)).toBe(true);
  });
  it("keeps the most generous of several subscriptions", () => {
    const entitlement = resolveEntitlement([sub({ currentPeriodEnd: days(-5) }), sub({ provider: "apple", currentPeriodEnd: days(300) }), sub({ currentPeriodEnd: days(10) })], now);
    expect(entitlement.source).toBe("appStore");
    expect(entitlement.expiresAt?.getTime()).toBe(days(300).getTime());
  });
});
