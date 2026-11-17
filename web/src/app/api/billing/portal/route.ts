import { NextResponse } from "next/server";
import { withUser } from "@/lib/api";
import { stripeClient } from "@/lib/billing";
import { prisma } from "@/lib/db";

export const POST = withUser(async (request, user) => {
  const stripe = stripeClient();
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  if (!stripe || !profile.stripeCustomerId) return NextResponse.json({ error: "No Stripe subscription on this account" }, { status: 404 });
  const origin = process.env.APP_URL ?? new URL(request.url).origin;
  const session = await stripe.billingPortal.sessions.create({ customer: profile.stripeCustomerId, return_url: `${origin}/settings` });
  return NextResponse.json({ url: session.url });
});
