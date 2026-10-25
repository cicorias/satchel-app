# Work items

Committed work tracking (ADR-0018). The conventions are in `docs/agents/issue-tracker.md`. Each folder is one feature or phase, with a `spec.md` and `issues/NN-*.md`.

| Folder | What | Order |
|---|---|---|
| [`phase-0-foundations/`](phase-0-foundations/spec.md) | spikes and human-only setup | spikes done; 05–07 are yours |
| [`phase-1-capture-engine/`](phase-1-capture-engine/spec.md) | model, capture engine, renderer, golden fixtures | done (ticket 10 waits for Defuddle 0.19.5) |
| [`phase-3-iphone/`](phase-3-iphone/spec.md) | iPhone app, Share Extension, Safari extension, CloudKit sync | 01–11 done; 12 now, 13 in release-1 |
| [`release-1/`](release-1/spec.md) | first App Store release (iPhone) | in App Store review; 09 is the first update |
| [`phase-2-chrome-edge/`](phase-2-chrome-edge/spec.md) | Chrome and Edge extensions on CloudKit Web Services | **next: start with 01** (host permission), then 02 (Spike A) |
| [`ideas/`](ideas/spec.md) | future feature ideas: one-liners, expanded into tickets later | intake only; not scheduled |

**Start here (2026-10-25):** `phase-2-chrome-edge/issues/01-host-permission-icloud-content.md` is the first ticket to pick up. It's small, unblocked, and agent-only. The Mac app comes after Phase 2 (ADR-0011).

To find the next item, look for files with `Status: ready-for-agent` (or `ready-for-human`) whose `Blocked by:` tickets are all `resolved`. Take them lowest-numbered first.
