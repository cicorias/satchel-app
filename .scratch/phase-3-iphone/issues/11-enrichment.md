# Enrichment of pending links

Status: ready-for-agent
Type: task
Blocked by: 06

§9.2.4 "Enrichment":
- **Loading:** for items with `metadataStatus: pending`, load the URL in a hidden, non-persistent `WKWebView` (no cookies from Safari), inject `capture.iife.js`, call `captureLink`, and merge the result. Set `complete`, or `failed` after N attempts.
- **Limits:** rate-limit requests per host, add timeouts, and skip enrichment on cellular when Low Data Mode is on.
- **When it runs:** on foreground and from background refresh. It must never block the UI.

**Done when** a link shared from another app shows its title, site, and image after the app enriches it (acceptance criterion). The scheduling and retry logic is unit-tested with a fake loader, and a fixture page served from a local file proves the injection path.
