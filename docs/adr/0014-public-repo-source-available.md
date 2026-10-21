# ADR-0014: Public repository, source-available license, no secrets

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

The developer wants the code visible publicly but intends to ship Satchel commercially on the App Store, Chrome Web Store, and Edge Add-ons. A public repo raises the stakes for leaked credentials (Team ID, App Store Connect API keys, CloudKit tokens).

## Decision

- The repository `cicorias/satchel-app` is **public** under a **source-available, all rights reserved** license: viewing is permitted; redistribution and publishing derivatives to any store are not.
- Third-party dependencies (Defuddle, Turndown, and other MIT or permissive packages) are attributed in `THIRD_PARTY_NOTICES.md`.
- **No secrets in the repo.** The Apple Team ID, App Store Connect API key, and CloudKit API tokens live in the gitignored `config/local.config.json`, in `~/.appstoreconnect/`, or in environment variables.
- **gitleaks** runs in a pre-commit hook (`.githooks/`, installed by `mise run setup`) and in CI. GitHub secret scanning and push protection are enabled on the repo.
- CloudKit web API tokens are not secret per the spec (§8.3; they ship in the client), but they are still kept out of the repo until Phase 7 decides how they are injected into store builds.

## Consequences

- Anyone can read the code; the license, not obscurity, protects the commercial product.
- Contributors (including agents) must never commit secrets to tracked files; the hook and CI catch mistakes.
- Build scripts must merge `config/app.config.json` with `config/local.config.json` and fail clearly when local values are missing.

## Alternatives considered

- *MIT:* allows clones to be published to the stores.
- *Apache-2.0:* same concern as MIT, with a patent grant that adds nothing here.
- *Private repo:* simplest for secrets, but the developer wants the code public.
