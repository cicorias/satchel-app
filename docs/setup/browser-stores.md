# Browser store setup (Chrome/Edge phase)

You already have a **Chrome Web Store** developer account and an **Edge Partner Center** account. None of this is needed until the Chrome/Edge phase (ADR-0011).

## Before the first upload

1. **Reserve the extension IDs early.** Upload a first draft zip (`mise run deploy:extension-zips`) to each store *without publishing*. Each store assigns its own extension ID, and Spike A needs both IDs for CloudKit sign-in callbacks (`https://<id>.chromiumapp.org/`, spec §8.3).
2. **Record the IDs** in `config/app.config.json` under a new `web.extensionIds` key. They aren't secret.

## Listing assets (rendered by `mise run art`)

| Store | Asset | File |
|---|---|---|
| Chrome | Store icon 128×128 | `store/chrome/icon-128.png` |
| Chrome | Small promo tile 440×280 | `store/chrome/promo-small-440x280.png` |
| Chrome | Marquee 1400×560 | `store/chrome/promo-marquee-1400x560.png` |
| Edge | Logo 300×300 | `store/edge/logo-300.png` |
| Edge | Small / large promo tiles | `store/edge/promo-small-440x280.png`, `store/edge/promo-large-1400x560.png` |
| Both | Screenshots 1280×800 | captured in the Chrome/Edge phase |

## Listing text and policy

- **Privacy policy URL:** https://cicorias.github.io/satchel-app/privacy.html
- **Support URL:** https://cicorias.github.io/satchel-app/support.html
- **Single purpose:** "Save the current page as a link or as Markdown to the user's own iCloud storage."
- **Permission justifications** (spec §9.1.2):

  | Permission | Justification |
  |---|---|
  | `activeTab`, `scripting` | Read the current page only when the user clicks Save. |
  | `storage` | Settings, the sign-in token, and the offline save queue. |
  | `contextMenus` | Right-click "Save page / link / selection". |
  | `alarms` | Retry queued saves and sync periodically. |
  | `identity` | Sign in with Apple ID for the user's own iCloud. |
  | `offscreen` | Parse HTML when saving a link without opening it. |
  | host `api.apple-cloudkit.com` | Write saves to the user's iCloud (CloudKit). |
  | optional `<all_urls>` | Requested only on first "save link target", to fetch its title. |
- **Data usage disclosures:** no data is collected by the developer. Content goes only to the user's own iCloud.
