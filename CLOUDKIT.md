# Deploying the CloudKit schema

Mealy syncs its SwiftData store through CloudKit (container `iCloud.work.pumpkinpatch.mealy`, private database). When a release changes the data model, the new fields must reach the **Production** schema before that release ships. TestFlight and App Store builds only use Production, and a build that saves a field Production doesn't have fails to sync.

Deploying takes two steps. First, a development build writes the new fields into the **Development** schema. Then you promote that schema to Production in the CloudKit Console.

## 1. Get the new fields into the Development schema

CloudKit only adds a field to the Development schema after a development build saves a record that uses it.

1. On an iPhone or simulator, sign in to iCloud in Settings, using a test or personal Apple Account.
2. Run the release branch from Xcode. A run from Xcode is a development build that syncs to the Development environment.
3. In the app, use the new feature so a record with the new field is saved (see "Model changes by release" below).
4. Leave the app open for a minute so it can sync. Xcode's console should show CloudKit export messages and no errors.

## 2. Check them in the CloudKit Console

1. Go to [icloud.developer.apple.com](https://icloud.developer.apple.com) → **CloudKit Database**, and pick the container `iCloud.work.pumpkinpatch.mealy`.
2. Switch the environment selector to **Development**.
3. Open **Schema** → **Record Types** and find the record type. SwiftData names record types `CD_<Model>` and fields `CD_<property>`.
4. Check that every new field is listed. If one is missing, the sync didn't happen: check that the device is signed in to iCloud, then repeat step 1.

## 3. Deploy to Production

1. Still in Development, click **Deploy Schema Changes…**. Depending on the Console version, it may be under **Schema** → **Deploy to Production**.
2. The review screen should list only the expected additions. Confirm.
3. Switch to **Production** and check that the new fields appear there.

## Things to know

- **No undo:** fields deployed to Production can't be deleted or renamed. Adding fields is safe, but deploy only once the release's model is final.
- **Order:** deploy before uploading the build to TestFlight.
- **Older versions:** older app versions ignore fields they don't know, so mixed versions on one iCloud account still sync.
- **Push entitlement:** `GroceryManager.entitlements` has `aps-environment = development`. Xcode switches it to production when you archive for distribution, so you don't need to change it.

## Model changes by release

### 1.2.0

- `CD_MealPlanEntry` gains **`CD_leftoverOf`**, the link from a planned leftovers meal to the meal it comes from (`MealPlanEntry.leftoverOf`). It is probably stored as a String reference ID, but check the type in the Console. The inverse list (`storedLeftovers`) isn't stored as a field.
- To create it in step 1: plan a dinner and turn on **Cook extra for tomorrow's lunch**, or choose it from a planned meal's menu.
- On 1.1.x a leftovers lunch shows as an ordinary lunch.
