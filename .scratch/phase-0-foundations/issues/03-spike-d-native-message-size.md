# Spike D: native message size limit (Safari)

Status: ready-for-agent
Type: prototype
Blocked by: 01

ADR-0007 consequence. Measure the largest payload `browser.runtime.sendNativeMessage` reliably delivers to `SafariWebExtensionHandler` on iOS.

## Do

- Add a temporary debug action in the extension that sends payloads of 64 KB, 256 KB, 1 MB, 4 MB, and 10 MB, and records success, failure, and round-trip time.
- Run it on the simulator and, if possible, on a device (a device needs ticket 04).

## Done when

- An addendum to ADR-0007 records the reliable limit and decides whether `begin`/`chunk`/`commit` chunking is needed (spec §9.1.3), and if so at what chunk size.
- The temporary debug code is removed.
