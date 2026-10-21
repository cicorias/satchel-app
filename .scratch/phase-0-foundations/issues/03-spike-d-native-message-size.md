# Spike D: native message size limit (Safari)

Status: resolved
Type: prototype
Blocked by: 01

ADR-0007 consequence. Measure the largest payload `browser.runtime.sendNativeMessage` reliably delivers to `SafariWebExtensionHandler` on iOS.

## Do

- Add a temporary debug action in the extension that sends payloads of 64 KB, 256 KB, 1 MB, 4 MB, and 10 MB, and records success, failure, and round-trip time.
- Run it on the simulator and, if possible, on a device (a device needs ticket 04).

## Done when

- An addendum to ADR-0007 records the reliable limit and decides whether `begin`/`chunk`/`commit` chunking is needed (spec §9.1.3), and if so at what chunk size.
- The temporary debug code is removed.

## Answer

2026-10-21, on the simulator. **No limit up to 64 MB** extension → native, and 16 MB native → extension. **Chunking isn't needed**, given the 10 MB page cap.
- The first message after a cold start takes ~1.4 s; warm messages take ~2 ms. The popup should `ping` on open to warm the handler (kept in the handler).
- Details are in the ADR-0007 addendum. The probe code is saved in `../research/03-spike-d-probe.md`, and the debug code has been removed from the app.
- Device verification is tracked in `08-verify-native-messaging-on-device.md`.
