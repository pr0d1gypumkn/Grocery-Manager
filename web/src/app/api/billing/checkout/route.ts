import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { PLANS, stripeClient, type Period } from "@/lib/billing";
import { prisma } from "@/lib/db";

/** Starts a Stripe Checkout session for the web. iOS uses StoreKit instead. */
export const POST = withUser(async (request, user) => {
  const body = z.object({ period: z.enum(["monthly", "yearly"]) }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "period must be monthly or yearly" }, { status: 400 });
  const stripe = stripeClient();
  const price = process.env[PLANS[body.data.period as Period].stripePriceEnv];
  if (!stripe || !price) return NextResponse.json({ error: "Stripe is not configured (STRIPE_SECRET_KEY, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_YEARLY)" }, { status: 503 });

  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  let customerId = profile.stripeCustomerId;
  if (!customerId) {
    const customer = await stripe.customers.create({ email: profile.email ?? undefined, metadata: { userId: user.id } });
    customerId = customer.id;
    await prisma.user.update({ where: { id: user.id }, data: { stripeCustomerId: customerId } });
  }
  const origin = process.env.APP_URL ?? new URL(request.url).origin;
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer: customerId,
    line_items: [{ price, quantity: 1 }],
    success_url: `${origin}/settings?upgraded=1`,
    cancel_url: `${origin}/settings`,
    metadata: { userId: user.id },
    subscription_data: { metadata: { userId: user.id } },
  });
  return NextResponse.json({ url: session.url });
});
