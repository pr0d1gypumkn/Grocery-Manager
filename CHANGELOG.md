# Changelog

## 1.1.2 (3) — 2026-11-22

Changes since 1.1.1 (3). Build 3 replaces builds 1 and 2 (see "Build 2" and "Build 3" below).

### New
- **Household sharing is live.** The app now connects to the Mealy server (mealy.pumpkinpatch.work), so Plus subscribers can share plans, lists and the pantry with their household. Subscribers are signed in automatically from their purchase; household members join with Sign in with Apple.
- **Quick add with an amount.** Type "500 g greek yogurt" or "2 lb chicken thighs" in the name field and the amount, unit and name are filled in for you.
- **Smarter new pantry items.** Category, storage spot and expiry date are suggested from the name (milk → Dairy, fridge, 10 days) until you pick them yourself.
- **New amount control.** One field for the amount and its unit, with − and + buttons that step in sizes that suit the unit (whole items, tidy gram steps, quarter cups) and a unit menu that lists your measurement system first.

### Improved
- Pantry item form is reorganised into clearer sections, with a "Running low" section explaining when an item gets flagged.
- Recipe ingredient rows use the same compact amount and unit control.
- Ingredients and recipe steps are matched by their root words, so the prep planner keeps steps that are only partly shared between recipes.
- Recipe import: notes in parentheses move to the ingredient note, hyphenated package sizes ("2-pound bag") and more container words are understood, and names from on-device import are cleaned up the same way.
- "Demo data" is now called "Sample data" in Settings.
- Subscription plan buttons have more room around their text, rounded corners and readable white text on the yearly plan.

### Fixed
- Saving the App Store account token before a purchase now uses the correct request, so a subscription always links to your existing account.
- If the server ends your session (expired, revoked or account deleted), the app signs you out cleanly, and subscribers are signed back in automatically, instead of failing silently.
- Sessions from older test builds or a different server are cleared at launch.
- The yearly plan's "Save %" badge now shows; a rounding bug hid it.

### Privacy and App Store
- Privacy policy updated to cover what server-backed Plus features send (recipe ideas and social import) and web accounts. It is now hosted at https://mealy.pumpkinpatch.work/privacy.
- Price-aware shopping stays hidden until a real price source is connected.
- Grocery checkout is hidden until full cart hand-off to retailers works.

### Server
- Accepts sandbox purchases (TestFlight and App Review) by default; set `APPLE_ALLOW_SANDBOX=0` to refuse them.
- Web sign-in never shows the sign-in code in production when the email can't be sent.
- Next.js 15.5.29 and React 19.0.9 (security updates).
- Deployment scripts for EC2 and RDS (`web/deploy/`), and a documented `.env.example`.

### Build 2
- Grocery checkout hidden in the app and on the web, and removed from the privacy policy.
- Yearly plan description no longer says "2 months free" (local StoreKit test prices now $2.99/month and $24.99/year to match App Store Connect).
- "Save %" badge fix and plan button styling (above).

### Build 3
- Storage on iPad and the open iPhone Duo: locations stack in two independent columns, so a short card no longer leaves a gap beside a tall one.
- Storage picks one or two columns from the available width instead of the device type, so the iPhone Duo's inner screen gets two columns and its outer screen one.
- App Store screenshots for iPhone 6.9", iPad 13" and iPhone Duo (App Store/Screenshots/).
