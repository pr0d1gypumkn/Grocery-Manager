# Mealy: App Store listing

Copy for App Store Connect, for version 1.2.0. Character limits are App Store Connect's; counts are checked in the table at the end.

Only features that are live in this build are described. Price-aware shopping and grocery checkout are hidden, so they aren't mentioned anywhere here. Add them back when they ship.

---

## App information

| Field | Value |
| --- | --- |
| **Name** (30) | Mealy - Meal Plan & Grocery |
| **Subtitle** (30) | Weekly planner, pantry & prep |
| **Primary category** | Food & Drink |
| **Secondary category** | Lifestyle |
| **Bundle ID** | work.pumpkinpatch.mealy |
| **Privacy Policy URL** | https://mealy.pumpkinpatch.work/privacy |
| **Support URL** | https://mealy.pumpkinpatch.work/support (contact: mealy@pumpkinpatch.work) |
| **Marketing URL** (optional) | https://mealy.pumpkinpatch.work |
| **Copyright** | 2026 Pumpkin Patch |
| **Age rating** | 4+ (answer "None" to every content question; no unrestricted web access, no user-generated content shared with strangers, no gambling) |

The name and subtitle together already cover "meal", "plan", "grocery", "weekly", "planner", "pantry" and "prep", so the keywords below don't repeat them. App Store search indexes all three fields.

---

## Promotional text (170)

Can be changed at any time without a new build.

> New: see your whole week at a glance, cook extra for tomorrow's lunch, and swap any meal in one tap. Plan, shop and prep without the Sunday-night scramble.

---

## Keywords (100)

```
recipe,shopping,list,leftovers,batch,cooking,dinner,food,inventory,expiry,kitchen,nutrition,fridge
```

Commas, no spaces. Singular forms are enough; the App Store matches plurals.

---

## Description (4000)

> Mealy runs the whole food week in one loop: plan your meals, build the grocery list, stock the pantry, batch-prep, eat the leftovers, and plan again.
>
> PLAN THE WEEK
> • See one day in detail or the whole week at a glance, with breakfast, lunch and dinner for every day
> • Drag meals between days and slots, or tap an empty slot to fill it
> • Cook extra for tomorrow's lunch: Mealy scales the recipe, buys the ingredients once, and plans the leftovers for you
> • Swap any meal for the best alternative from your own recipes, ranked by what's already in your pantry
> • A gentle nudge shows which days still need a dinner
> • Nutrition per meal, per day and as a weekly average
>
> SHOP WHAT YOU NEED
> • Your grocery list builds itself from the plan, with matching ingredients merged across recipes
> • Items you already have are left off
> • Sorted by store section so you walk the aisles once
> • Check items off and they go straight into your pantry
>
> KNOW WHAT'S IN THE KITCHEN
> • Keep stock by fridge, freezer and pantry
> • Quick add: type "500 g greek yogurt" and the amount, unit and name are filled in
> • Category, storage spot and expiry date are suggested from the name
> • Reminders before things expire, and "Use it up" recipes for what's about to go off
> • Cooking a planned meal takes its ingredients out of stock
>
> BATCH-PREP IN ONE SESSION
> • Turn the week's recipes into a single prep session
> • Steps the recipes share are merged and ordered, with timers
> • Portion the results into containers and track them in stock
>
> YOUR RECIPES, ANY SOURCE
> • Import a recipe from a website link
> • Adjust servings and every amount scales
> • Metric and US units, converted for you
>
> WORKS YOUR WAY
> • No account needed. Your data stays on your device and syncs with iCloud
> • Built for iPhone and iPad, including side-by-side days on larger screens
> • Siri and Shortcuts support
> • Export your data any time
>
> MEALY PLUS
> Everything above is free. Plus adds:
> • Automatic planning: a full week planned from your recipes, tastes, pantry and household in one tap
> • New recipe ideas matched to your tastes and what's in the pantry
> • Social and photo import: pull recipes from TikTok, Instagram and YouTube links, screenshots, photos and handwritten cards
> • Household sharing: share plans, lists and the pantry with everyone at home, with portions per person
>
> Plus is available as a monthly or yearly auto-renewing subscription. Payment is charged to your Apple Account when you confirm. The subscription renews automatically at the same price unless you cancel at least 24 hours before the end of the current period. Manage or cancel it in your Apple Account settings. If it lapses, nothing is deleted; only Plus features pause.
>
> Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
> Privacy Policy: https://mealy.pumpkinpatch.work/privacy

---

## What's New in This Version (4000)

> Weekly planning, rebuilt.
>
> • Week view: switch between Day and Week on the Plan tab to see every breakfast, lunch and dinner at once. Tap an empty slot to fill it, or drag meals between days.
> • Plan leftovers: choose "Cook extra for tomorrow's lunch" and Mealy scales the meal, buys the ingredients once, and plans the leftovers for the next day.
> • Swap a meal: replace any planned meal with the best alternative from your recipes, ranked by what's already in your pantry. Planned leftovers follow along.
> • Dinners left to plan: a nudge shows which days still need a dinner.
> • Weekly nutrition: a daily average per person across the week.
>
> Fixes
> • "Plan my week for me" now fills every slot, even when you have fewer recipes than meals to plan.
> • The weekly budget is shared across the week instead of applied to each meal.
> • Leftovers are no longer counted twice in nutrition totals.

---

## Subscriptions

Subscription group: **Mealy Plus**. Both products need a display name, a description, a review screenshot (`App Store/subscription-review-screenshot.png`) and review notes.

| Product ID | Display name (35) | Description (55) | Price |
| --- | --- | --- | --- |
| work.pumpkinpatch.mealy.plus.monthly | Mealy Plus Monthly | Auto planning, recipe ideas, import and sharing | $2.99 / month |
| work.pumpkinpatch.mealy.plus.yearly | Mealy Plus Yearly | All Plus features, billed yearly at a lower price | $24.99 / year |

Group display name: **Mealy Plus**.

---

## App Privacy (nutrition label)

From `PrivacyInfo.xcprivacy` and `PRIVACY.md`. Tracking: **No**. None of the data is used for tracking or advertising.

| Data type | Collected | Linked to user | Purpose |
| --- | --- | --- | --- |
| User ID | Yes (Plus and household members only) | Yes | App Functionality |
| Purchase History | Yes | Yes | App Functionality |
| Email Address | Yes (Sign in with Apple, web accounts) | Yes | App Functionality |
| Other User Content (plans, lists, pantry, recipes sent for import) | Yes (Plus server features only) | Yes | App Functionality |

Data that stays on the device or in the user's own iCloud isn't "collected" under Apple's definition, so free-tier use collects nothing. Photos are picked with the system picker and read on the device.

---

## App Review information

**Sign-in:** none needed. The app works without an account. Plus subscribers are signed in automatically from their purchase.

**Notes for the reviewer:**

> Mealy works fully without an account. On first launch it loads sample recipes, a week's meal plan and a stocked pantry so every screen can be tried right away (Settings › Your data › Load sample data reloads it).
>
> To try 1.2.0's changes: on the Plan tab, switch to Week. Long-press a dinner and choose "Cook extra for tomorrow's lunch" or "Swap for another recipe".
>
> Mealy Plus is an auto-renewable subscription (monthly or yearly) that unlocks automatic planning, recipe ideas, social and photo import, and household sharing. It can be bought in the sandbox from any locked feature or from the Plan section at the top of Settings. Household sharing connects to our server at mealy.pumpkinpatch.work; a household member joins with Sign in with Apple.
>
> Account deletion: Settings › Account › Delete account (shown once signed in).

Fill in a contact name, phone number and email for the review team in App Store Connect.

---

## Screenshots

Upload in this order. App Store Connect needs the 6.9" iPhone set and the 13" iPad set. It scales them down for smaller devices, so the 6.3" set is optional.

| Order | iPhone 6.9" / 6.3" | iPad 13" |
| --- | --- | --- |
| 1 | 01-meal-plan | 01-meal-plan |
| 2 | 02-week (6.3" only) | 02-stock |
| 3 | stock | 03-storage |
| 4 | storage | 04-recipes |
| 5 | recipes | 05-recipe-detail |
| 6 | recipe-detail | 06-groceries |
| 7 | groceries | |

The 6.9" and iPad sets were taken on 1.1.2 and don't show the Week view.

---

## Still to do before submitting

1. **Support page.** Deploy the web app so https://mealy.pumpkinpatch.work/support is live, and check that mealy@pumpkinpatch.work receives mail.
2. **CloudKit schema.** Deploy `CD_leftoverOf` to Production before uploading 1.2.0 (see `CLOUDKIT.md`).
3. **Copyright holder.** "Pumpkin Patch" is a guess from the domain; use your legal name or company.
4. **Category.** Food & Drink fits best. Lifestyle and Productivity are the usual second choices.
5. **Week view screenshots.** Optionally retake the 6.9" and iPad sets on 1.2.0 so they include the Week view.
