import Stripe from "stripe";
import { prisma } from "./db";

// Both stores write Subscription rows; nothing else in the app knows which store a user used.

export const PLANS = {
  monthly: { stripePriceEnv: "STRIPE_PRICE_MONTHLY", appleProductId: "work.pumpkinpatch.mealy.plus.monthly" },
  yearly: { stripePriceEnv: "STRIPE_PRICE_YEARLY", appleProductId: "work.pumpkinpatch.mealy.plus.yearly" },
} as const;

export type Period = keyof typeof PLANS;

export function stripeClient(): Stripe | null {
  const key = process.env.STRIPE_SECRET_KEY;
  return key ? new Stripe(key) : null;
}

export function periodForProduct(productId: string): Period {
  return productId.endsWith("yearly") || productId === process.env.STRIPE_PRICE_YEARLY ? "yearly" : "monthly";
}

export async function upsertSubscription(input: {
  userId: string;
  provider: "apple" | "stripe";
  providerSubscriptionId: string;
  productId: string;
  status: string;
  currentPeriodEnd: Date;
  isInGracePeriod?: boolean;
  environment?: string;
}) {
  const period = periodForProduct(input.productId);
  return prisma.subscription.upsert({
    where: { providerSubscriptionId: input.providerSubscriptionId },
    update: { status: input.status, currentPeriodEnd: input.currentPeriodEnd, isInGracePeriod: input.isInGracePeriod ?? false, productId: input.productId, period },
    create: {
      userId: input.userId,
      provider: input.provider,
      providerSubscriptionId: input.providerSubscriptionId,
      productId: input.productId,
      period,
      status: input.status,
      currentPeriodEnd: input.currentPeriodEnd,
      isInGracePeriod: input.isInGracePeriod ?? false,
      environment: input.environment ?? "production",
    },
  });
}

/** Maps a Stripe subscription status onto our vocabulary. */
export function statusFromStripe(status: Stripe.Subscription.Status): string {
  switch (status) {
    case "active":
    case "trialing":
      return "active";
    case "past_due":
      return "grace";
    case "canceled":
    case "unpaid":
    case "incomplete_expired":
      return "expired";
    default:
      return "expired";
  }
}
