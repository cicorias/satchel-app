# Platform adapters

All `chrome.*` / `browser.*` access outside entry points lives here (spec §9.1.3):

- `types.ts`: the `PlatformAdapter` interface the popup uses.
- `tab.ts`: the active tab, and `captureTab`, which injects `capture.js` and runs `captureLink`/`capturePage` plus `itemFromCapture` in the page.
- `safari.ts`: Safari, through `browser.runtime.sendNativeMessage` to `SafariWebExtensionHandler` (messages in SatchelKit's `ExtensionMessageHandler`).
- `chromium.ts`: Chrome/Edge, IndexedDB outbox → CloudKit Web Services (Phase 2). Until then `index.ts` has a stub that reports saving isn't available yet.
