import { NextRequest, NextResponse } from "next/server";
import { FeatureLockedError, hasFeature, type Feature } from "./entitlements";
import { userFromRequest, type SessionUser } from "./auth";

type Handler = (request: NextRequest, user: SessionUser, context: { params: Promise<Record<string, string>> }) => Promise<Response>;

/** Wraps an API route: requires a signed-in user and, optionally, one Plus feature. */
export function withUser(handler: Handler, feature?: Feature) {
  return async (request: NextRequest, context: { params: Promise<Record<string, string>> }) => {
    const user = await userFromRequest(request);
    if (!user) return NextResponse.json({ error: "Sign in required" }, { status: 401 });
    try {
      if (feature && !(await hasFeature(user.id, feature))) throw new FeatureLockedError(feature);
      return await handler(request, user, context);
    } catch (error) {
      if (error instanceof FeatureLockedError) {
        return NextResponse.json({ error: error.message, feature: error.feature, upgrade: "/settings#billing" }, { status: 402 });
      }
      console.error(error);
      return NextResponse.json({ error: error instanceof Error ? error.message : "Unexpected error" }, { status: 500 });
    }
  };
}
