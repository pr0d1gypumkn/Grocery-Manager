import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { prisma } from "@/lib/db";
import { checkoutProvidersFor } from "@/lib/prices/registry";

const schema = z.object({
  provider: z.string().optional(),
  region: z.enum(["US", "CA"]).optional(),
  lines: z.array(z.object({ name: z.string(), quantity: z.number().default(1), unit: z.string().default("item") })).max(200),
});

/** Lists checkout providers for the region, or builds a link for one of them. */
export const POST = withUser(async (request, user) => {
  const body = schema.safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "lines[] required" }, { status: 400 });
  const profile = await prisma.user.findUniqueOrThrow({ where: { id: user.id } });
  const region = body.data.region ?? (profile.region as "US" | "CA");
  const providers = checkoutProvidersFor(region);
  if (!body.data.provider) {
    return NextResponse.json({ providers: providers.map((p) => ({ key: p.key, name: p.name })) });
  }
  const provider = providers.find((p) => p.key === body.data.provider);
  if (!provider?.checkoutURL) return NextResponse.json({ error: "Unknown provider" }, { status: 404 });
  return NextResponse.json({ provider: provider.key, url: await provider.checkoutURL(body.data.lines) });
}, "checkout_links");
