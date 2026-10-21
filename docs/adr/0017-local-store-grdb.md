# ADR-0017: GRDB + SQLite for the Apple local store

- **Status:** Accepted
- **Date:** 2026-10-21

## Context

On Apple platforms, the host app, the Share Extension, and the Safari extension handler all read and write the local cache and outbox (§9.2.1). These run as separate processes, often concurrently, sharing the App Group container. The library needs full-text search over title, description, site, tags, and body (FR-7).

## Decision

- Use **GRDB** over **SQLite in WAL mode**, with the database file in the App Group container (`group.com.cedarlogic.satchel`).
- The same database holds the local cache and the outbox for all three targets.
- Library search uses **SQLite FTS5**.
- Access goes through `SatchelKit` only.

## Consequences

- WAL allows concurrent readers with one writer across processes, which suits short-lived extensions writing while the app syncs.
- FTS5 gives fast, ranked local search with no extra dependency.
- Schema migrations are explicit (GRDB `DatabaseMigrator`) and must be safe when an older extension process opens a newer database.

## Alternatives considered

- *SwiftData:* weak multi-process concurrency in App Group containers and no first-class full-text search.
- *Raw SQLite C API:* no dependency, but much more boilerplate and easier to misuse.
