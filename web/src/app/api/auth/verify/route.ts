import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { setSessionCookie, signToken, verifyCode } from "@/lib/auth";

export async function POST(request: NextRequest) {
  const body = z.object({ email: z.string().email(), code: z.string().min(6).max(6) }).safeParse(await request.json().catch(() => ({})));
  if (!body.success) return NextResponse.json({ error: "Email and 6-digit code are required" }, { status: 400 });
  const user = await verifyCode(body.data.email, body.data.code);
  if (!user) return NextResponse.json({ error: "That code is wrong or has expired" }, { status: 401 });
  const token = await signToken(user);
  await setSessionCookie(token);
  return NextResponse.json({ token, userId: user.id, email: user.email });
}
