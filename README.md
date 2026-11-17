# Mealy (Grocery Manager)

Plan → shop → stock the pantry → batch-prep → eat leftovers → plan again.

| Part | Stack | Where |
| --- | --- | --- |
| iOS app | SwiftUI, SwiftData + CloudKit, StoreKit 2 | `GroceryManager/` |
| Server + web app | Next.js 15, Postgres (Prisma), Stripe | `web/` |

The free tier runs entirely on-device with no account. Plus features (prices, auto-planning, suggestions, social/photo import, household sharing, checkout links) use the server once the user signs in.

## iOS

Open `GroceryManager.xcodeproj` in Xcode 27+. The scheme uses `GroceryManager/Mealy.storekit`, so subscriptions can be bought in the simulator. On first launch an empty store is filled with demo data (Settings ▸ Your data ▸ Load demo data to reset). Settings ▸ Plan has a "Demo: unlock Plus" switch.

Tests: `xcodebuild test -scheme GroceryManager -destination 'platform=iOS Simulator,name=iPhone 17'`

The paid gate lives in one place: `EntitlementService.hasFeature(_:)` in `GroceryManager/Services/Entitlements.swift`.

## Server and web

See `web/README.md`. Point the app at it in Settings ▸ Account ▸ Server URL (default `http://localhost:3000`).
