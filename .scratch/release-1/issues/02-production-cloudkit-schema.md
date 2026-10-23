# Deploy the CloudKit schema to Production

Status: ready-for-human
Type: task
Blocked by: -

TestFlight and App Store builds use CloudKit's **Production** environment. Every test so far ran Debug builds against Development, and Production has no `Item` record type yet. Until it does, saves from release builds fail to reach iCloud.

1. Check that Development matches the repo: `mise run deploy:cloudkit-schema diff` shows no changes.
2. [CloudKit Console](https://icloud.developer.apple.com) → container `iCloud.com.cedarlogic.satchel` → **Development** → **Deploy Schema Changes…** → review the list (record type `Item` and its fields, plus indexes) → **Deploy**.
3. Confirm: `ENV=production mise run deploy:cloudkit-schema diff` shows no changes (`docs/setup/apple.md` §4).

Fields can't be removed or retyped once they're in Production, so this step is permanent.
