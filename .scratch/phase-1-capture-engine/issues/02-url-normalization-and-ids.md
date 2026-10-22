# Model: URL normalization v1 and deterministic IDs

Status: resolved
Type: task
Blocked by: 01

Spec §7.2 steps 1–7, and `ItemId = "u_" + first 32 hex of SHA-256(normalizedUrl)`. The registrable-domain check in step 7 needs a public-suffix approach; choose one and justify any new dependency in the commit message.

**Done when** table-driven tests cover every rule (tracking parameters, `www.`, default ports, hashbang, parameter sort order, trailing slash, cross-domain canonical).

## Answer

`packages/model/src/url.ts` contains:
- `normalizeUrl`, for steps 1–6.
- `identityUrl`, for step 7.
- `normalizedUrlFor`, which runs the whole algorithm.
- `itemIdFor`.
- `NORMALIZATION_VERSION = 1`.

`test/url.test.ts` has a table-driven case for every rule, plus idempotence and rejection cases. A further test checks that every `fixtures/model/` item derives its own `normalizedUrl` and `id`.

Decisions:
- **Query encoding is kept as written.** Parameters are filtered and sorted as raw `key=value` segments. They are sorted by decoded key, and tracking keys match case-insensitively. Re-serializing with `URLSearchParams` would rewrite `%20` as `+` and change IDs for the same URL.
- **Only one trailing `/` is removed**, as §7.2 says.
- **Same site uses the PSL's private section** (`tldts`, with `allowPrivateDomains`), so `alice.github.io` and `bob.github.io` count as different sites. Hosts with no registrable domain (IP addresses, `localhost`) must match exactly. A relative canonical is resolved against the page URL first.
- **Dependencies:** `tldts` provides the maintained Public Suffix List, and `@noble/hashes` provides SHA-256. `@noble/hashes` is synchronous and works where `crypto.subtle` doesn't, such as non-secure contexts. That covers Share Extension preprocessing on `http:` pages and `WKWebView` with `loadHTMLString`.
