import { redirect } from "next/navigation";
import { currentUser, requestCode, setSessionCookie, signToken, verifyCode } from "@/lib/auth";
import { sendCodeEmail } from "@/lib/mail";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ email?: string; sent?: string; error?: string; devCode?: string }> }) {
  if (await currentUser()) redirect("/");
  const params = await searchParams;

  async function send(formData: FormData) {
    "use server";
    const email = String(formData.get("email") ?? "").trim();
    if (!email.includes("@")) redirect("/login?error=Enter+a+valid+email");
    const { code } = await requestCode(email);
    const delivered = await sendCodeEmail(email, code);
    if (!delivered && process.env.NODE_ENV === "production") {
      // Never reveal the code in production: anyone could then sign in as any email.
      redirect("/login?error=We+couldn%27t+send+the+code.+Please+try+again+later.");
    }
    redirect(`/login?sent=1&email=${encodeURIComponent(email)}${delivered ? "" : `&devCode=${code}`}`);
  }

  async function verify(formData: FormData) {
    "use server";
    const email = String(formData.get("email") ?? "");
    const code = String(formData.get("code") ?? "");
    const user = await verifyCode(email, code);
    if (!user) redirect(`/login?sent=1&email=${encodeURIComponent(email)}&error=Wrong+or+expired+code`);
    await setSessionCookie(await signToken(user));
    redirect("/");
  }

  return (
    <div style={{ maxWidth: 420, margin: "40px auto" }}>
      <h1>Sign in</h1>
      <p className="lede">Accounts are only needed for Plus features that sync through the server. The iOS app's free features work without one.</p>
      {params.error ? <div className="error">{params.error}</div> : null}
      {params.sent ? (
        <form action={verify} className="card grid">
          <input type="hidden" name="email" value={params.email ?? ""} />
          <p>We emailed a 6-digit code to <strong>{params.email}</strong>.</p>
          {params.devCode ? <div className="notice">No mail provider configured. Your code is <strong>{params.devCode}</strong>.</div> : null}
          <input name="code" inputMode="numeric" placeholder="123456" maxLength={6} required autoFocus />
          <button className="primary" type="submit">Sign in</button>
        </form>
      ) : (
        <form action={send} className="card grid">
          <input name="email" type="email" placeholder="you@example.com" required autoFocus />
          <button className="primary" type="submit">Send sign-in code</button>
        </form>
      )}
    </div>
  );
}
