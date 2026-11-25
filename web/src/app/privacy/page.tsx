import type { Metadata } from "next";

export const metadata: Metadata = { title: "Privacy Policy · Mealy" };

// Public copy of the privacy policy, the Privacy Policy URL in App Store Connect
// (https://mealy.pumpkinpatch.work/privacy). Keep in sync with PRIVACY.md and the in-app
// PrivacyPolicyView in GroceryManager/Views/PaywallView.swift.
export default function PrivacyPage() {
  return (
    <article style={{ maxWidth: 720, margin: "24px auto", lineHeight: 1.55 }}>
      <h1>Mealy Privacy Policy</h1>
      <p className="muted"><em>Last updated November 21, 2026</em></p>

      <h2>The short version</h2>
      <p>Mealy works without an account. Your recipes, meal plans, grocery lists and pantry stay on your device and in your own iCloud. We don&apos;t sell your data, show ads, or track you across apps or websites.</p>

      <h2>Data on your device and in iCloud</h2>
      <p>Everything you add is stored on your device. If iCloud is on, Apple syncs it through your private iCloud database so it appears on your other devices. We can&apos;t read your iCloud data.</p>

      <h2>Photos</h2>
      <p>When you import a recipe from a photo, the text is read on your device. The photo isn&apos;t uploaded or kept.</p>

      <h2>Recipe links</h2>
      <p>When you import a recipe from a web, TikTok, Instagram or YouTube link, the app downloads that page to read the recipe from it.</p>

      <h2>Your Apple ID and household sharing</h2>
      <p>Some Plus features, such as household sharing, use our server. There&apos;s no separate Mealy account:</p>
      <ul>
        <li>If you subscribe, your App Store purchase identifies you.</li>
        <li>If you join someone&apos;s household, you use Sign in with Apple.</li>
      </ul>
      <p>We store an anonymous Apple user ID, your subscription status, your email only if you choose to share it through Sign in with Apple, and the household data you share. We use these only to provide those features. You can delete all of it at any time in <strong>Settings ▸ Account ▸ Delete account</strong>. This also revokes Mealy&apos;s access to your Apple ID.</p>

      <h2>Requests to our server</h2>
      <p>While you&apos;re signed in, a few Plus features ask our server for help:</p>
      <ul>
        <li>Recipe ideas send the names of your saved recipes, pantry items and diet preferences.</li>
        <li>Social import sends the post&apos;s link.</li>
      </ul>
      <p>These are used only to answer that request and aren&apos;t stored.</p>

      <h2>Web accounts</h2>
      <p>If you use Mealy on the web, you sign in with a one-time code sent to your email. We store your email address to sign you in. Web subscriptions are handled by Stripe; we never see your full card details.</p>

      <h2>Purchases</h2>
      <p>App Store subscriptions are handled by Apple. We receive a signed confirmation of your subscription from Apple, never your payment details.</p>

      <h2>Notifications</h2>
      <p>Expiry reminders are scheduled on your device. Nothing about them is sent to us.</p>

      <h2>Children</h2>
      <p>Mealy isn&apos;t directed at children under 13, and we don&apos;t knowingly collect their personal information.</p>

      <h2>Changes and contact</h2>
      <p>If this policy changes, we&apos;ll update the date above. For questions, contact us through the support link on the App Store page.</p>
    </article>
  );
}
