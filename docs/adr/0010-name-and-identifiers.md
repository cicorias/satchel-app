# ADR-0010: Product name and identifiers

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

The spec (v0.1) used "Stash" as a working name and left the final name, bundle prefix, and iCloud container open (§15, question 1). Identifiers such as the iCloud container and App Group are effectively permanent once created in the Apple Developer portal, so they must be settled before Phase 0 portal work.

## Decision

- **Product name:** Satchel. Lowercase slug: `satchel`.
- **GitHub repository:** `cicorias/satchel-app` (public; see ADR-0014).
- **Apple team:** CedarLogic LLC. The Team ID is kept out of the repo, in the gitignored `config/local.config.json`.
- **Identifiers** (lowercase suffix style):

| Identifier | Value |
|---|---|
| App bundle ID | `com.cedarlogic.satchel` |
| Share Extension | `com.cedarlogic.satchel.share` |
| Safari Web Extension | `com.cedarlogic.satchel.safari` |
| App Group | `group.com.cedarlogic.satchel` |
| iCloud container | `iCloud.com.cedarlogic.satchel` |
| Keychain access group | `$(AppIdentifierPrefix)com.cedarlogic.satchel.shared` |
| URL scheme | `satchel://` |

- **Code names** are Satchel-prefixed: Xcode targets `Satchel`, `SatchelShare`, `SatchelSafari`; Swift package `SatchelKit`; npm scope `@satchel/*`; IIFE globals `globalThis.SatchelCapture` and `globalThis.SatchelRender`.
- All of the above derive from `config/app.config.json` (§12.5); no identifier is hard-coded elsewhere.

## Consequences

- Resolves spec §15 open question 1.
- `docs/setup/apple.md` can now name exact values for App IDs, the App Group, and the iCloud container.
- Code identifiers match the product name, so search and navigation stay obvious.
- Renaming later is still possible through the config file, but the iCloud container and App Group cannot be deleted or renamed in the portal, so a rename would orphan them.

## Alternatives considered

- *Xcode-template PascalCase suffixes* (`com.cedarlogic.satchel.ShareExtension`): mixed case in IDs is error-prone and inconsistent with the App Group and container.
- *Neutral code names* (e.g. `App`, `Kit`, `ShareExt`): rename-proof, but less readable and collide easily in search and in Xcode's UI.
