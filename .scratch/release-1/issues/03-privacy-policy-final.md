# Finalize the privacy policy

Status: resolved
Type: task
Blocked by: -

`site/privacy.html` is marked "Draft". Bring it in line with what the iPhone app actually does, then remove the draft note:
- **Enrichment** (Phase 3 ticket 11): to fill in a link saved from another app, the app downloads that page's HTML once (no cookies, nothing else from the page), so that site sees one request.
- **Remote images:** off by default in store builds; "Load images" and the Settings switch contact the original sites.
- The local copy lives in the app's App Group container, the extensions save straight to the user's iCloud, and nothing goes to CedarLogic.
- Chrome and Edge tokens: keep that paragraph, but mark it as applying when those extensions ship.

The App Store's privacy questionnaire answer is **Data Not Collected**. Legal review (`../../phase-0-foundations/issues/07-legal-review-license-and-privacy.md`) reads the final text.

## Answer

`site/privacy.html` has an effective date of October 23, 2026, and is no longer marked Draft.
- It covers the app's local copy and its extensions, link details (one HTML download, with no cookies, subresources, or scripts), and images loading only by choice.
- Chrome and Edge are marked "when available".
- `site/support.html` no longer says iCloud Drive is required.
- The user's legal review accepted it (2026-10-23).
