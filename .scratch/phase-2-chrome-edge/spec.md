# Phase 2: Chrome and Edge extensions

Source: `docs/spec.md` §14 Phase 2, §8.3 (CloudKit access per platform), §9.1 (web extension), and ADR-0004, ADR-0007, ADR-0011. Opened 2026-10-25 while release 1 waits for App Store review.

## Storage path per browser (decided; recorded 2026-10-25)

| Browser | Path | Auth |
|---|---|---|
| Safari (iOS, later macOS) | `sendNativeMessage` → `SafariWebExtensionHandler` → App Group outbox → CloudKit framework (ADR-0007) | Device iCloud account. Safari never calls CloudKit Web Services |
| Chrome / Edge | CloudKit Web Services REST, called **only from the background service worker** | `ckAPIToken` + `ckWebAuthToken` |

Rejected for Chrome/Edge:
- **CloudKit JS:** the supported way to load it is from Apple's CDN, which MV3 forbids (remotely hosted code). Apple doesn't license it for redistribution or publish it on npm. It also needs a window (`window.open` + `postMessage` sign-in, cookie or `localStorage` sessions), and an MV3 service worker has neither. It wraps the same REST endpoints we call directly.
- **Server-to-server keys:** public database only.
- **Our own backend as a proxy:** breaks "storage the user owns."

Safari notes: if the Safari popup needs library reads (recent saves, "already saved?"), it goes through the native handler to the GRDB store, never CloudKit.

## Order

1. **01: host permission for CloudKit asset hosts.** Small, agent-only, unblocked. Do it first.
2. **02: Spike A.** CloudKit Web Services sign-in from the extension. Needs CloudKit Console tokens (human), then a throwaway extension (agent).
3. The provider and sync tickets get written from Spike A's answers.

## Done when

`docs/spec.md` §14 Phase 2's boxes are ticked.
