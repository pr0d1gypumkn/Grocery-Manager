import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { subscriptionStateFrom, verifyAppleJWS, type DecodedTransaction } from "@/lib/appstore";
import { appleBundleID } from "@/lib/apple";
import { PLANS, upsertSubscription } from "@/lib/billing";
import { signToken, userFromRequest } from "@/lib/auth";
import { prisma } from "@/lib/db";

const PRODUCT_IDS: Set<string> = new Set(Object.values(PLANS).map((plan) => plan.appleProductId));

/**
 * Silent iOS sign-in from an App Store purchase: no email, no password, no sign-in screen.
 * The app posts the signed transaction StoreKit gave it; Apple's signature proves the
 * purchase, and the subscription (originalTransactionId) is the identity. The same
 * subscription always maps to the same Mealy user, across reinstalls and devices.
 */
export async function POST(request: NextRequest) {
  const body = z.object({
    signedTransaction: z.string().min(20),
    appAccountToken: z.string().uuid().optional(),
  }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "signedTransaction is required" }, { status: 400 });

  let transaction: DecodedTransaction;
  try {
    transaction = await verifyAppleJWS<DecodedTransaction>(body.data.signedTransaction);
  } catch {
    return NextResponse.json({ error: "That purchase couldn't be verified." }, { status: 401 });
  }
  if (transaction.bundleId !== appleBundleID() || !PRODUCT_IDS.has(transaction.productId)) {
    return NextResponse.json({ error: "That purchase isn't for Mealy." }, { status: 401 });
  }
  // App Review and TestFlight purchase in the sandbox, even against the production server, so
  // sandbox purchases are accepted unless explicitly turned off (APPLE_ALLOW_SANDBOX=0).
  if (transaction.environment === "Sandbox" && process.env.APPLE_ALLOW_SANDBOX === "0") {
    return NextResponse.json({ error: "Sandbox purchases aren't accepted by this server." }, { status: 401 });
  }

  // Who owns this subscription? Existing row, then the account token set at purchase,
  // then whoever is already signed in (e.g. via Sign in with Apple), else a new user.
  const existing = await prisma.subscription.findUnique({
    where: { providerSubscriptionId: transaction.originalTransactionId },
    select: { userId: true },
  });
  const token = transaction.appAccountToken ?? body.data.appAccountToken;
  const byToken = !existing && token ? await prisma.user.findUnique({ where: { appleAppAccountToken: token } }) : null;
  const current = !existing && !byToken ? await userFromRequest(request) : null;
  const userId = existing?.userId
    ?? byToken?.id
    ?? current?.id
    ?? (await prisma.user.create({ data: { appleAppAccountToken: token ?? null } })).id;

  const state = subscriptionStateFrom(transaction, undefined, "SIGN_IN");
  await upsertSubscription({
    userId,
    provider: "apple",
    providerSubscriptionId: transaction.originalTransactionId,
    productId: transaction.productId,
    ...state,
  });

  const user = await prisma.user.findUniqueOrThrow({ where: { id: userId } });
  const sessionToken = await signToken({ id: user.id, email: user.email });
  return NextResponse.json({ token: sessionToken, userId: user.id, email: user.email });
}
