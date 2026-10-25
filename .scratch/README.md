# Work items

Committed work tracking (ADR-0018). The conventions are in `docs/agents/issue-tracker.md`. Each folder is one feature or phase, with a `spec.md` and `issues/NN-*.md`.

| Folder | What | Order |
|---|---|---|
| [`phase-0-foundations/`](phase-0-foundations/spec.md) | spikes and human-only setup | spikes done; 05–07 are yours |
| [`phase-1-capture-engine/`](phase-1-capture-engine/spec.md) | model, capture engine, renderer, golden fixtures | done (ticket 10 waits for Defuddle 0.19.5) |
| [`phase-3-iphone/`](phase-3-iphone/spec.md) | iPhone app, Share Extension, Safari extension, CloudKit sync | 01–11 done; 12 now, 13 in release-1 |
| [`release-1/`](release-1/spec.md) | first App Store release (iPhone) | **now**: bookmark and checklist |
| [`ideas/`](ideas/spec.md) | future feature ideas: one-liners, expanded into tickets later | intake only; not scheduled |

Phase 2 (Chrome/Edge) gets its folder after release 1, and the Mac app after that (ADR-0011).

To find the next item, look for files with `Status: ready-for-agent` (or `ready-for-human`) whose `Blocked by:` tickets are all `resolved`. Take them lowest-numbered first.
