import type { Metadata } from "next";
import "./globals.css";
import { currentUser } from "@/lib/auth";
import { NavLinks } from "@/components/NavLinks";

export const metadata: Metadata = { title: "Mealy", description: "Plan, shop, stock, prep, eat, repeat." };
export const dynamic = "force-dynamic";

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const user = await currentUser();
  return (
    <html lang="en">
      <body>
        <nav className="top">
          <a className="brand" href="/">Mealy</a>
          {user ? <NavLinks /> : null}
          <span className="spacer" />
          {user ? (
            <form action="/api/auth/logout" method="post" className="inline">
              <span className="muted">{user.email ?? "Signed in with Apple"}</span>
              <button className="small" type="submit">Sign out</button>
            </form>
          ) : (
            <a className="btn primary" href="/login">Sign in</a>
          )}
        </nav>
        <main>{children}</main>
      </body>
    </html>
  );
}
