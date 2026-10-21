# Platform adapters

All `chrome.*` / `browser.*` access outside entry points lives here (spec §9.1.3):

- `chromium.ts` — Chrome/Edge: IndexedDB outbox → CloudKit Web Services (Phase 2)
- `safari.ts` — Safari: `browser.runtime.sendNativeMessage` → `SafariWebExtensionHandler` (Phase 3)
