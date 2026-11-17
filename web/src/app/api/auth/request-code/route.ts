import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { requestCode } from "@/lib/auth";
import { sendCodeEmail } from "@/lib/mail";

export async function POST(request: NextRequest) {
  const body = z.object({ email: z.string().email() }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "A valid email is required" }, { status: 400 });
  const { code } = await requestCode(body.data.email);
  console.log(`Request code for ${body.data.email}: ${code}`);
  const delivered = await sendCodeEmail(body.data.email, code);
  // In development (no mail provider) the code is returned so the flow can be tried end to end.
  return NextResponse.json({ ok: true, ...(delivered ? {} : { devCode: code }) });
}
