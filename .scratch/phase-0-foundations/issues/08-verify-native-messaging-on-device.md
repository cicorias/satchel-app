# Verify native messaging on a physical iPhone

Status: resolved
Type: prototype
Blocked by: 04

Spike D was measured on the simulator only (ADR-0007 addendum). Repeat it on a device once signed device builds work.

## Do

- Re-apply the probe from `../research/03-spike-d-probe.md`, then build signed for the device (`SIGNED=1 DESTINATION="platform=iOS,name=<iPhone>" mise run build:ios`).
- Enable the extension and open the popup on an article page. Record the summary, or read the `SPIKE` lines in Console.app.

## Done when

- The ADR-0007 addendum notes the device limit and cold-start time, and it still says that no chunking is needed (or that chunking is needed, and at what size).
- The probe code has been removed again.

## Answer

Done on 2026-10-22 on an iPhone 18 Pro Max (ADR-0007, second addendum).

- Requests up to **32 MB** arrive intact, and **64 MB** fails with "Couldn't communicate with a helper application". Responses up to 16 MB arrive intact. With the 10 MB page cap, there's still no chunking.
- The first message after install took **69 ms** (1.4 s on the simulator), and warm round trips take 1–2 ms. The `ping` warm-up stays as cheap insurance.
- Reading results on a device: `devicectl device copy from` only reaches `Library/`, `Documents/`, and `tmp/` in the App Group container, and collecting the device log needs root. The probe now writes `Library/spike-d-report.jsonl`; see `../research/03-spike-d-probe.md`.
- The probe code was removed again.
