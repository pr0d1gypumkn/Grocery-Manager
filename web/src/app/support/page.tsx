import type { Metadata } from "next";

export const metadata: Metadata = { title: "Support · Mealy" };

const SUPPORT_EMAIL = "mealy@pumpkinpatch.work";

// Public support page, the Support URL in App Store Connect
// (https://mealy.pumpkinpatch.work/support). Keep the answers in step with the iOS app.
export default function SupportPage() {
  return (
    <article style={{ maxWidth: 720, margin: "24px auto", lineHeight: 1.55 }}>
      <h1>Mealy Support</h1>
      <p>
        Questions, problems or ideas? Email{" "}
        <a href={`mailto:${SUPPORT_EMAIL}?subject=Mealy%20support`}>{SUPPORT_EMAIL}</a>. We usually reply within two
        business days. If something isn&apos;t working, include your device, iOS version and Mealy version (Settings ▸
        About) so we can help faster.
      </p>

      <h2>Getting started</h2>
      <p>
        Mealy works without an account. On first launch it loads sample recipes, a meal plan and a stocked pantry so you
        can try everything. To bring the samples back later, tap <strong>Load sample data</strong> in{" "}
        <strong>Settings ▸ Your data</strong>.
      </p>

      <h2>My data isn&apos;t showing on my other devices</h2>
      <p>
        Mealy syncs through your private iCloud. On each device, check that you&apos;re signed in to the same Apple
        Account and that iCloud is on for Mealy in <strong>Settings ▸ [your name] ▸ iCloud</strong>. Changes can take a
        minute to appear.
      </p>

      <h2>Mealy Plus</h2>
      <ul>
        <li>
          <strong>Restore a purchase:</strong> in Mealy, open Settings and tap <strong>Restore purchases</strong>.
        </li>
        <li>
          <strong>Manage or cancel:</strong> tap <strong>Manage subscription</strong> in Mealy&apos;s Settings, or go to{" "}
          <strong>Settings ▸ [your name] ▸ Subscriptions</strong> on your iPhone. Cancel at least 24 hours before the
          period ends to avoid renewal.
        </li>
        <li>
          <strong>Refunds:</strong> App Store purchases are refunded by Apple. Request one at{" "}
          <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>.
        </li>
        <li>If Plus lapses, nothing is deleted. Only Plus features pause.</li>
      </ul>

      <h2>Household sharing</h2>
      <p>
        The person with Plus shares an invite code from the <strong>Sharing</strong> section of Settings. Everyone else
        joins with that code and Sign in with Apple. Joining is free; the owner&apos;s Plus covers the household.
      </p>

      <h2>Export your data</h2>
      <p>
        Go to <strong>Settings ▸ Your data</strong> to export everything as JSON, or your grocery list and pantry as CSV.
      </p>

      <h2>Delete your account</h2>
      <p>
        If you&apos;ve signed in for Plus or household sharing, go to <strong>Settings ▸ Account ▸ Delete account</strong>.
        This removes everything stored on our server and revokes Mealy&apos;s access to your Apple ID. Data on your device
        and in your iCloud stays until you delete the app.
      </p>

      <h2>Privacy</h2>
      <p>
        Read the <a href="/privacy">privacy policy</a>. Mealy doesn&apos;t show ads or track you.
      </p>
    </article>
  );
}
