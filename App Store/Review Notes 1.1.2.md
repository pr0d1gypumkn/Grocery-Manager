# App Review notes for 1.1.2 (5)

App Review replied to 1.1.2 (3) with **Guideline 2.1 - Information Needed**. This was a request for more information, not a reported bug. They asked for six things in the Notes field of **App Review Information**, plus a screen recording.

1. Paste the block under "Notes" into **App Store Connect › App Store › 1.1.2 › App Review Information › Notes**. It is under the 4,000-character limit.
2. Record the video using "Screen recording" below. Attach it in the **Attachment** field of the same section. If it's too big, upload it somewhere that needs no sign-in and put the link where the notes say.
3. Pick build 5. It fixes recipe import on devices without Apple Intelligence (build 4) and ingredient matching for names like "diced carrots" (build 5).
4. Make sure both Plus subscriptions are attached to this version, under **In-App Purchases and Subscriptions** on the version page.
5. Resubmit.

---

## Notes (paste this)

```
1. SCREEN RECORDING
Attached: a recording on an iPhone running the latest iOS. It starts at launch and shows meal planning, the grocery list, the pantry, batch prep, recipe import, buying Mealy Plus (sandbox), Sign in with Apple for household sharing, and account deletion.

2. PURPOSE AND AUDIENCE
Mealy is a meal planner for home cooks and households who want to spend less time and waste less food. It runs one weekly loop: plan meals, build the grocery list from the plan, keep track of what's in the fridge, freezer and pantry, batch-prep the week, and plan again. It removes the need to write lists by hand, buy duplicates or throw out food that expired.

3. SETUP AND MAIN FEATURES
No account or login is needed. On first launch Mealy loads sample recipes, a week of meals and a stocked pantry, so every screen can be tried right away (Settings › Your data › Load sample data reloads it).
- Plan tab: the week's meals; tap a day, use + to add a meal, long-press a meal to move, copy or repeat it, tap the pan to mark it cooked.
- Groceries tab: the list built from the plan; check items off to add them to stock.
- Stock and Storage tabs: the pantry by location, with expiry dates.
- Recipes tab: recipes; the import button (top right) imports from a note, a website, a social post or a photo.
Mealy Plus (auto-renewable, monthly or yearly) adds automatic week planning, recipe ideas, social and photo import, and household sharing. Buy it with a sandbox account from any "Plus" card or from the top of Settings. Plus subscribers are signed in automatically from their purchase; no login screen.
Household sharing: in Settings › Sharing, the subscriber shares an invite code; another person joins with that code and Sign in with Apple.
Account deletion: Settings › Account › Delete account (shown once signed in). It deletes the server account and revokes Sign in with Apple.
User-generated content is never public. Plans, lists and recipes are shared only inside a household the user invited, so there is nothing to report or block.

4. EXTERNAL SERVICES
- Apple iCloud (CloudKit, private database): syncs the user's own data between their devices.
- Apple In-App Purchase (StoreKit 2) and App Store Server Notifications: Mealy Plus subscriptions.
- Sign in with Apple: identifies household members.
- Apple Foundation Models and Vision, both on-device: reading recipes from notes and photos. No third-party AI service is used. Without Apple Intelligence, an on-device text parser is used instead.
- Mealy server (mealy.pumpkinpatch.work, our own, hosted on AWS): household sync, recipe ideas and social import, for Plus only.
- Recipe websites, and TikTok, Instagram and YouTube public oEmbed pages: only the page the user enters is fetched, to read the recipe.

5. REGIONS
The app works the same in every region. The Region and Units settings only change how amounts are shown (metric or US units).

6. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
Not applicable. Mealy is not in a regulated industry and ships no licensed third-party content. Sample recipes are our own; imported recipes come from the link or text the user provides.
```

---

## Screen recording

Apple asked for a recording made on a **physical device** running the latest iOS, **starting from launch**. Record on your iPhone with Control Center › Screen Recording. About 3–4 minutes is enough. Don't narrate; tapping slowly is better.

**Before recording:**
- Delete Mealy from the iPhone, then install build 5 from TestFlight so the first launch loads the sample data.
- Settings › App Store › Sandbox Account: sign in with a sandbox tester so the purchase is free. TestFlight purchases also use the sandbox.
- For the household step, have a second device or a second Apple Account ready, or show only the invite code (see step 8).
- Turn on Do Not Disturb.

**Shot list:**
1. **Launch:** start on the Home Screen and tap Mealy. Show the launch screen and the Plan tab with the sample week.
2. **Plan:** tap a couple of days. Tap + and add a meal. Long-press a meal and use Move to tomorrow. Tap the pan on a meal to mark it cooked.
3. **Groceries:** open the list. Check off two items and show the "added to stock" message.
4. **Stock and Storage:** scroll the pantry, open an item, and show its expiry date.
5. **Recipes:** open a recipe and change the servings. Go back, tap import, choose Note, paste a short recipe, and tap Parse. Show the new recipe.
6. **Batch prep:** Plan tab › "Batch-cook this week in one session". Show the merged steps.
7. **Buy Plus:** tap a Plus card, such as "New recipe ideas". Show the plans, buy monthly with the sandbox account, and show that New recipe ideas now opens. Optionally show "Plan my week for me" on the Plan tab.
8. **Household sharing / login:** Settings › Sharing. Show the invite code and Share invite. If you have a second device, join with the code and Sign in with Apple there, and show the shared plan.
9. **Account deletion:** Settings › Account › Delete account. Confirm it and show that you're signed out.
10. **Restore:** Settings › Restore purchases, so the reviewer sees it works.

Stop the recording and trim the start and end in Photos. Export it as a video under 500 MB.

---

## Also check

- **Subscriptions submitted with the version.** App Review mentions Guideline 3.1.1. If the subscriptions aren't attached to 1.1.2, the paywall shows "Plans aren't available right now" during review.
- **Screenshots** show the app in use (the 6.9" iPhone, iPad and Duo sets in `App Store/Screenshots/`). Don't use the 6.3" set for 1.1.2.
- **Contact information** in App Review Information is filled in.
