# Safari extension: save links and pages from the popup through the native handler

Status: ready-for-agent
Type: task
Blocked by: 06

ADR-0007 and §9.1, Safari part only. Chrome and Edge get their platform adapter in Phase 2.

- **Popup UI** (`apps/extension/src/entrypoints/popup`), shared with Chrome and Edge later:
  - "Save link" (primary) and "Save page", optional tags with autocomplete, and a note (FR-5).
  - Confirmation, plus "Replace saved copy?" when the native side reports `replacesBody` (FR-6).
  - Send `ping` when the popup opens (ADR-0007 addendum).
- **Capture:** inject `packages/capture` into the active tab on the user's action (`activeTab` + `scripting`, §11), and run `captureLink`/`capturePage` there.
- **Platform adapter** (`apps/extension/src/platform/`): `saveItem`, `status`, and `tags`, implemented for Safari with `browser.runtime.sendNativeMessage`. Nothing else may call `browser.*` (AGENTS.md).
- **`SafariWebExtensionHandler`:** handle `save` (validate, enforce the 10 MB cap with a clear error, `Store.save`, then `OneShotSaver`), `status`, and `tags`. Keep `ping`.

**Done when**:
- `mise run test:ios-ui` gains a test that saves a link and a page from the Safari popup on the simulator, and the item appears in the library with its body.
- The handler's message handling is unit-tested in SatchelKit (move the logic out of the extension target).
