# ADR-0007: Safari saves through native code

- **Status:** Accepted
- **Date:** 2026-10-21

**Context.** Safari does not support the `identity` API. Using CloudKit Web Services from Safari would require an Apple ID web sign-in on a device that is already signed in to iCloud.

**Decision.** The Safari extension sends captures with `browser.runtime.sendNativeMessage` to `SafariWebExtensionHandler`, which writes to the App Group outbox and then saves through the CloudKit framework.

**Consequences.**
- ✅ No sign-in on Apple devices.
- ✅ Same write path as the Share Extension.
- ✅ Future OAuth providers work through the host app and a shared Keychain.
- ⚠️ The Safari save path includes Swift code.
- ⚠️ The native message size limit must be verified (Spike D), with chunking as the fallback.
- ⚠️ The handler is short-lived, so it always writes to the durable outbox before attempting the network save.

## Addendum — 2026-10-21: Spike D results (native message size)

Measured on the iPhone 18 Pro Max simulator (iOS 27.0, Xcode 27.1) from the popup and from the background service worker, with `browser.runtime.sendNativeMessage` → `SafariWebExtensionHandler`. The payload was a JSON message carrying an ASCII string. The handler checked the received UTF-8 byte count against the declared size.

| Direction | Sizes tried | Result | Time at the largest size |
|---|---|---|---|
| extension → native | 64 KB … **64 MB** | every size delivered intact | ~300–330 ms |
| native → extension | 64 KB … **16 MB** | every size delivered intact | ~180 ms |

- **No size limit was hit** up to 64 MB. The spec caps a page capture at 10 MB (§4.4), so **`begin`/`chunk`/`commit` chunking isn't needed**, and the handler will accept one `save` message. If a device test shows a lower limit, revisit this.
- **Cold start:** the first native message after the extension process starts takes **~1.3–1.4 s**. Warm round trips take ~2 ms. To meet the 1-second link-save confirmation (§3.2), the popup should send a `ping` when it opens, so the handler process is warm by the time the user taps Save. The handler keeps `ping` for this.
- **Still to verify on a physical iPhone** once the Apple portal setup is done: `.scratch/phase-0-foundations/issues/08-verify-native-messaging-on-device.md`.
