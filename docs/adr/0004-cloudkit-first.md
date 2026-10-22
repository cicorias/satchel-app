# ADR-0004: CloudKit first, behind a provider abstraction

- **Status:** Accepted
- **Amended by:** [ADR-0011](0011-delivery-order-iphone-first.md) (Spike A timing and phase order)
- **Date:** 2026-10-21

**Context.** The app is personal today and heading to the stores. The developer must not pay for users' storage. Target devices are Apple devices plus Chrome and Edge on Windows and other platforms.

**Decision.** Use the CloudKit private database as the v1 and only provider. Define the provider-neutral storage contract (§8.1) now, and add file-based providers (Dropbox, Google Drive, OneDrive) in Phase 6.

**Reasons.**
- Private-database storage counts against the user's own iCloud quota, not the developer's.
- Zero sign-in on Apple devices, where most saving will happen.
- Mature sync primitives: custom zones, change tokens, CKSyncEngine, push notifications.
- A clear privacy story: the developer never has access to user data.

**Consequences.**
- Chrome and Edge users must have an Apple ID and sign in through Apple's web flow; the extension sign-in needs a spike (§8.3).
- Requires the paid Apple Developer Program.
- The CloudKit schema must be deployed to Production before release.
- CloudKit Web Services is older and less documented than the native API, so the TypeScript adapter stays small and heavily tested.
- Data-model choices (separate body, deterministic IDs, tombstones, provider-neutral image paths) were made so they map cleanly onto file-based providers later.

**Alternatives considered.**
- *Dropbox first:* simplest cross-platform API, but requires OAuth on every device including Apple ones.
- *Supabase or Firebase:* the developer pays for all users' data.
- *Local-only with Syncthing:* no workable iOS story.

## Addendum (2026-10-22): the schema is a file, applied with `cktool`

The schema in spec §8.2 is kept as CloudKit Schema Language in `apple/CloudKit/Satchel.ckdb` and applied with Xcode's `xcrun cktool` through `mise run deploy:cloudkit-schema` (`validate`, `import`, `export`). This replaces the hand-entered Console steps in the first draft of `docs/setup/apple.md`.

- **Why:** the schema is reviewed in diffs like any other code, both environments can be checked against the file at any time, and a reset Development environment can be rebuilt with one command.
- **Auth:** a CloudKit management token, saved once with `xcrun cktool save-token --type management` into the macOS keychain. It never enters the repo or CI.
- **Limits:** `cktool` only imports into Development. Promoting to Production stays a deliberate Console action (**Deploy Schema Changes…**) before each release. CI doesn't touch CloudKit, because a management token in a public repo's CI isn't worth the risk.
