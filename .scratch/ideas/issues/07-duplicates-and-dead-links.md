# Duplicate and dead-link check

Status: needs-triage
Type: task
Blocked by: -

Find saves that point to the same thing, and links that no longer work. Expanded from idea 7 on 2026-10-25.

## Decisions so far

- **Dead links:** checked on demand only, with a "Check links" action in the app and in the extension manager. There's no background network traffic. Results become a filter (`dead`).
- **Fallback:** when a dead link has a saved page, the saved copy is offered as the fallback. There's no Wayback Machine lookup, to avoid sending URLs to a third party.
- **Near-duplicates:** these go beyond URL normalization (spec §7.2):
  - the same canonical URL (`<link rel="canonical">`);
  - redirects that end at the same place (short links, http → https);
  - the same title on the same site.
- **Resolution:** merge duplicates using the existing merge rules (§7.3): tags are combined, and the page wins over the link.

## Open questions

- **What counts as dead:** 404/410 and DNS failure count. Do 403, 5xx, and timeouts count too? Retry once before flagging?
- **Paywalls and bot blocks:** a check from the app can be blocked where your browser isn't. Chrome/Edge could run the check from the extension instead.
- **Following redirects** for duplicate detection makes one request per link, so it's also on demand only.

## Comments
