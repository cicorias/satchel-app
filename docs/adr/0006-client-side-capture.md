# ADR-0006: Client-side capture

- **Status:** Accepted
- **Date:** 2026-10-21

**Decision.** Capture from the live DOM on the client. Never fetch pages on a server. Link saves without a DOM (URLs shared from non-browser apps, right-clicked link targets) are enriched client-side: in an offscreen document in Chrome and Edge, and in a hidden `WKWebView` in the iOS/macOS host app.

**Reasons.** Captures what the user actually sees: logged-in content, paywalled content they have access to, JavaScript-rendered single-page apps, and pages with consent dialogs already dismissed. No server cost and no data leaves the user's devices except to their own storage.

**Consequences.** Enrichment sees the logged-out version of a page, and some sites block non-browser fetches. Both are acceptable for link metadata.
