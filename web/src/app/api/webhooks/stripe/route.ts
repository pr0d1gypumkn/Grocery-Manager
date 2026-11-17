import { NextRequest, NextResponse } from "next/server";
import type Stripe from "stripe";
import { statusFromStripe, stripeClient, upsertSubscription } from "@/lib/billing";
import { prisma } from "@/lib/db";

export async function POST(request: NextRequest) {
  const stripe = stripeClient();
  const secret = process.env.STRIPE_WEBHOOK_SECRET;
  if (!stripe || !secret) return NextResponse.json({ error: "Stripe webhook not configured" }, { status: 503 });
  const signature = request.headers.get("stripe-signature") ?? "";
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(await request.text(), signature, secret);
  } catch (error) {
    return NextResponse.json({ error: `Invalid signature: ${(error as Error).message}` }, { status: 400 });
  }
  const seen = await prisma.webhookEvent.findUnique({ where: { eventId: event.id } });
  if (seen) return NextResponse.json({ ok: true, duplicate: true });
  await prisma.webhookEvent.create({ data: { provider: "stripe", eventId: event.id, payload: event as unknown as object } });

  if (event.type.startsWith("customer.subscription.")) {
    const subscription = event.data.object as Stripe.Subscription;
    const customerId = typeof subscription.customer === "string" ? subscription.customer : subscription.customer.id;
    const user = (subscription.metadata?.userId && (await prisma.user.findUnique({ where: { id: subscription.metadata.userId } }))) || (await prisma.user.findUnique({ where: { stripeCustomerId: customerId } }));
    if (user) {
      const item = subscription.items.data[0];
      const periodEnd = (subscription as unknown as { current_period_end?: number }).current_period_end ?? Math.floor(Date.now() / 1000);
      await upsertSubscription({
        userId: user.id,
        provider: "stripe",
        providerSubscriptionId: subscription.id,
        productId: item?.price.id ?? "stripe",
        status: event.type === "customer.subscription.deleted" ? "expired" : statusFromStripe(subscription.status),
        currentPeriodEnd: new Date(periodEnd * 1000),
        isInGracePeriod: subscription.status === "past_due",
      });
    }
  }
  return NextResponse.json({ ok: true });
}
