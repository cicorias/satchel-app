# Apple setup

These steps create the identifiers, CloudKit container, and App Store Connect records that Satchel's targets expect. Use the **CedarLogic LLC** team throughout (ADR-0010), not the Personal Team, which can't provision iCloud containers.

| Thing | Value |
|---|---|
| App ID (host app) | `com.cedarlogic.satchel` |
| App ID (Share Extension) | `com.cedarlogic.satchel.share` |
| App ID (Safari extension) | `com.cedarlogic.satchel.safari` |
| App Group | `group.com.cedarlogic.satchel` |
| iCloud container | `iCloud.com.cedarlogic.satchel` |
| Keychain group | `<TeamID>.com.cedarlogic.satchel.shared` (no portal step needed) |
| URL scheme | `satchel://` |
| CloudKit custom zone | `Library` (created by the app at runtime) |

## 0. Local Team ID (automatic)

`mise run setup` reads the CedarLogic LLC Team ID from Xcode's signed-in accounts and writes it to the gitignored `config/local.config.json`. If it can't (on CI, or with a different machine or account), copy `config/local.config.example.json` to `config/local.config.json` and fill in the ID, which is under **developer.apple.com → Account → Membership details**. Never commit it.

## 1. Identifiers (developer.apple.com → Certificates, IDs & Profiles → Identifiers)

Create these in order, because the App IDs reference the group and container.

1. **App Group:** click **+** and choose **App Groups**. Description: `Satchel shared`. Identifier: `group.com.cedarlogic.satchel`.
2. **iCloud Container:** click **+** and choose **iCloud Containers**. Description: `Satchel`. Identifier: `iCloud.com.cedarlogic.satchel`.
3. **App IDs:** click **+**, choose **App IDs**, then **App**, and register each **explicit** bundle ID below.

   | Bundle ID | Description | Capabilities to enable, then **Configure** |
   |---|---|---|
   | `com.cedarlogic.satchel` | Satchel | **App Groups**: select `group.com.cedarlogic.satchel`. **iCloud**: choose *Include CloudKit support*, then select `iCloud.com.cedarlogic.satchel`. **Push Notifications** (for CloudKit change pushes). |
   | `com.cedarlogic.satchel.share` | Satchel Share Extension | **App Groups** (same group) and **iCloud** (same container, CloudKit). |
   | `com.cedarlogic.satchel.safari` | Satchel Safari Extension | **App Groups** (same group) and **iCloud** (same container, CloudKit). |

   Keychain sharing needs no portal capability. The `keychain-access-groups` entitlement only has to use the team prefix.

Provisioning profiles: leave them to Xcode. The project uses automatic signing, and the scripts pass `-allowProvisioningUpdates`.

## 2. Signing certificates

The login keychain currently has no code-signing identities. That's fine for simulator builds, which `mise run build:ios` runs unsigned. For device builds and archives:

1. Open Xcode → **Settings → Accounts**, select the Apple ID, then **CedarLogic LLC → Manage Certificates…**
2. Click **+** and add **Apple Development**. Later, add **Apple Distribution** for archives. Xcode can also use cloud-managed certificates, but local ones make CLI archives more predictable.

## 3. First device build

```sh
mise run apple:project
open apple/Satchel.xcodeproj   # choose your iPhone and Run, or:
SIGNED=1 DESTINATION="platform=iOS,name=<your iPhone name>" mise run build:ios
```

If Xcode reports a missing capability on an App ID, recheck step 1. The entitlements come from `apple/project.yml`, so the portal must match them.

## 4. CloudKit schema (scripted with `xcrun cktool`)

The schema lives in `apple/CloudKit/Satchel.ckdb` (spec §8.2): record type `Item`, its fields, and its indexes (`recordName`, `kind`, `normalizedUrl`, `tags` queryable; `createdAt` sortable). `mise run deploy:cloudkit-schema` pushes it with Xcode's `cktool`, so you don't need to click through the Console field by field.

1. **Create a management token.** In CloudKit Console (icloud.developer.apple.com), open **Settings → Tokens & Keys**, choose the **CedarLogic LLC** team, and create a **Management Token**. Copy it; it's shown once.
2. **Save it to your keychain** (never the repo):
   ```sh
   xcrun cktool save-token --type management   # paste at the secure prompt
   ```
3. **Check, then push, the schema** to the Development environment. The Team ID comes from `config/local.config.json` and the container from `config/app.config.json`.
   ```sh
   mise run deploy:cloudkit-schema validate
   mise run deploy:cloudkit-schema import
   ```
4. **First run only: reconcile the system types.** Export the live schema and diff it against the file. If the `Users` record type or the system-field lines differ from what CloudKit generated, copy CloudKit's version into `Satchel.ckdb`, then record what changed under `## Comments` in `.scratch/phase-0-foundations/issues/04-apple-portal-setup.md`.
   ```sh
   mise run deploy:cloudkit-schema diff   # exports, then diffs with comments ignored
   ```
5. Don't create the `Library` zone by hand. The app creates it.
6. Skip **API tokens** for CloudKit Web Services until the Chrome/Edge phase. Spike A decides the callback URLs (ADR-0011).

**Changing the schema later.** Edit `Satchel.ckdb` and run `import`. Production isn't scripted: `cktool` only imports into Development. Before a release (Phase 7), use CloudKit Console → **Deploy Schema Changes…** to promote Development to Production, then confirm with `ENV=production mise run deploy:cloudkit-schema diff`. Once a field is in Production it can't be deleted or retyped, so every field addition is permanent.

## 5. App Store Connect

1. **Apps → + → New App:** platform iOS. Name: **Satchel**. If that name is taken in the store, use something like *Satchel - Web Clipper*. Record it as `apple.appStoreName` in `config/app.config.json`, and leave `name` as **Satchel**. The store name only lives in App Store Connect and must be unique there. `name` is the label under the icon, which doesn't need to be unique and should stay short. Primary language English (U.S.), bundle ID `com.cedarlogic.satchel`, SKU `satchel-ios`, full access.
2. **TestFlight → Internal Testing →** create a group (e.g. `Developers`) and add yourself.
3. **App Store Connect API key** (for `mise run deploy:ios-upload`):
   1. Go to **Users and Access → Integrations → App Store Connect API → Team Keys**, click **+**, name it `satchel-upload`, and choose the **App Manager** role.
   2. Download `AuthKey_<KEYID>.p8` (you can only download it once) and move it to `~/.appstoreconnect/private_keys/`. **Never put it in the repo.** `.gitignore` and gitleaks both guard against it.
   3. Export these in your shell profile or in `~/.config/mise/config.toml` `[env]`. Don't put them in the repo's `mise.toml`.
      ```sh
      export ASC_KEY_ID=<KEYID>
      export ASC_ISSUER_ID=<issuer UUID shown above the keys table>
      ```

## 6. Release flow (once 1–5 are done)

```sh
mise run deploy:ios-archive   # signed Release archive + App Store Connect export
mise run deploy:ios-upload    # uploads to App Store Connect, then appears in TestFlight
```

Bump `version` in `config/app.config.json` (CalVer, ADR-0015) for each release. The build number is the git commit count, unless you set `BUILD_NUMBER`.
