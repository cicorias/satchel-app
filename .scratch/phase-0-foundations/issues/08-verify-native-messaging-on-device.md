# Verify native messaging on a physical iPhone

Status: ready-for-agent
Type: prototype
Blocked by: 04

Spike D was measured on the simulator only (ADR-0007 addendum). Repeat it on a device once signed device builds work.

## Do

- Re-apply the probe from `../research/03-spike-d-probe.md`, then build signed for the device (`SIGNED=1 DESTINATION="platform=iOS,name=<iPhone>" mise run build:ios`).
- Enable the extension and open the popup on an article page. Record the summary, or read the `SPIKE` lines in Console.app.

## Done when

- The ADR-0007 addendum notes the device limit and cold-start time, and it still says that no chunking is needed (or that chunking is needed, and at what size).
- The probe code has been removed again.
