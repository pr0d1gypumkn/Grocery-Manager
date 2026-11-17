import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { prisma } from "@/lib/db";
import { priceList } from "@/lib/prices/registry";

const schema = z.object({
  region: z.enum(["US", "CA"]).optional(),
  lines: z.array(z.object({ name: z.string(), quantity: z.number().default(1), unit: z.string().default("item") })).max(200),
  weeklyBudgetCents: z.number().int().optional(),
});

/** Estimated cost per line and for the list, from whichever price sources are configured. */
export const POST = withUser(async (request, user) => {
  const body = schema.safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "lines[] required" }, { status: 400 });
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  const region = body.data.region ?? (profile.region as "US" | "CA");
  const result = await priceList(region, body.data.lines);
  const budget = body.data.weeklyBudgetCents ?? profile.weeklyBudgetCents;
  return NextResponse.json({
    region,
    currency: result.currency,
    totalCents: result.totalCents,
    quotedCount: result.quotedCount,
    budgetCents: budget,
    overBudgetCents: budget > 0 ? Math.max(result.totalCents - budget, 0) : 0,
    lines: result.lines.map((line) => ({
      name: line.name, quantity: line.quantity, unit: line.unit,
      priceCents: line.quote?.priceCents ?? null, currency: line.quote?.currency ?? result.currency,
      store: line.quote?.storeName ?? null, storeKey: line.quote?.storeKey ?? null, isSale: line.quote?.isSale ?? false, label: line.quote?.label ?? null,
    })),
  });
}, "price_aware_shopping");
