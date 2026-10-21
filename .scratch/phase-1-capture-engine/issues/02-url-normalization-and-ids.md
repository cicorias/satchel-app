# Model: URL normalization v1 and deterministic IDs

Status: ready-for-agent
Type: task
Blocked by: 01

Spec §7.2 steps 1–7, and `ItemId = "u_" + first 32 hex of SHA-256(normalizedUrl)`. The registrable-domain check in step 7 needs a public-suffix approach; choose one and justify any new dependency in the commit message.

**Done when** table-driven tests cover every rule (tracking parameters, `www.`, default ports, hashbang, parameter sort order, trailing slash, cross-domain canonical).
