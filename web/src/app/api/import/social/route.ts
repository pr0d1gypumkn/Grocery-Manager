import { NextResponse } from "next/server";
import { z } from "zod";
import { withUser } from "@/lib/api";
import { importSocial } from "@/lib/social";

export const POST = withUser(async (request) => {
  const body = z.object({ url: z.string().url() }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "A valid URL is required" }, { status: 400 });
  return NextResponse.json(await importSocial(body.data.url));
}, "social_import");
