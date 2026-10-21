# ADR-0015: CalVer versioning

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

Satchel ships an iOS app with two extensions plus Chrome and Edge extensions built from the same web packages. Store version formats differ: Apple's `CFBundleShortVersionString` allows up to three period-separated integers; Chrome and Edge manifests allow one to four integers. The repo is a monorepo (ADR-0001) where changes land atomically across platforms.

## Decision

- Version format **CalVer `YYYY.M.PATCH`** (e.g. `2026.10.0`), with no leading zeros on the month.
- **One version** in `config/app.config.json`, shared by the iOS app, its extensions, and the web packages and browser extension.
- The **build number** (`CFBundleVersion`) is computed at build time from `git rev-list --count HEAD`, overridable with the `BUILD_NUMBER` environment variable.

## Consequences

- The same string is valid as `CFBundleShortVersionString` (three integers) and as a Chrome/Edge manifest `version`.
- The version shows when a build was cut, and every platform built from a commit reports the same version.
- A platform may get a version bump with no user-visible change; acceptable.
- Build numbers increase monotonically on the main branch; builds from shallow clones must fetch history or set `BUILD_NUMBER`.

## Alternatives considered

- *SemVer:* communicates compatibility, which matters for libraries, not for an app with no public API.
- *Independent versions per platform:* more bookkeeping and no benefit for a solo developer shipping from one repo.
