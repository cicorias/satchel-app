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
