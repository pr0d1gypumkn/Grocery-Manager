import { NextRequest, NextResponse } from "next/server";
import { subscriptionStateFrom, verifyAppleJWS, type DecodedNotification, type DecodedRenewalInfo, type DecodedTransaction } from "@/lib/appstore";
import { upsertSubscription } from "@/lib/billing";
import { prisma } from "@/lib/db";

/**
 * App Store Server Notifications V2. Apple posts a signed payload; we verify it, map the
 * transaction to a user via appAccountToken (set by the app at purchase) and store the state.
 */
export async function POST(request: NextRequest) {
  const body = (await request.json().catch(() => null)) as { signedPayload?: string } | null;
  if (!body?.signedPayload) return NextResponse.json({ error: "signedPayload required" }, { status: 400 });
  const allowUnverified = process.env.APPLE_ALLOW_UNVERIFIED === "1" && process.env.NODE_ENV !== "production";
  let notification: DecodedNotification;
  try {
    notification = await verifyAppleJWS<DecodedNotification>(body.signedPayload, { allowUnverified });
  } catch (error) {
    return NextResponse.json({ error: (error as Error).message }, { status: 400 });
  }
  const seen = await prisma.webhookEvent.findUnique({ where: { eventId: notification.notificationUUID } });
  if (seen) return NextResponse.json({ ok: true, duplicate: true });
  await prisma.webhookEvent.create({ data: { provider: "apple", eventId: notification.notificationUUID, payload: notification as unknown as object } });

  if (!notification.data?.signedTransactionInfo) return NextResponse.json({ ok: true });
  const transaction = await verifyAppleJWS<DecodedTransaction>(notification.data.signedTransactionInfo, { allowUnverified });
  const renewal = notification.data.signedRenewalInfo ? await verifyAppleJWS<DecodedRenewalInfo>(notification.data.signedRenewalInfo, { allowUnverified }) : undefined;
  const user = transaction.appAccountToken ? await prisma.user.findUnique({ where: { appleAppAccountToken: transaction.appAccountToken } }) : null;
  if (!user) return NextResponse.json({ ok: true, unmatched: true });

  const state = subscriptionStateFrom(transaction, renewal, notification.notificationType);
  await upsertSubscription({
    userId: user.id,
    provider: "apple",
    providerSubscriptionId: transaction.originalTransactionId,
    productId: transaction.productId,
    ...state,
  });
  return NextResponse.json({ ok: true });
}
