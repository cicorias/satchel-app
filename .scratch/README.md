# Work items

Committed work tracking (ADR-0018). The conventions are in `docs/agents/issue-tracker.md`. Each folder is one feature or phase, with a `spec.md` and `issues/NN-*.md`.

| Folder | What | Order |
|---|---|---|
| [`phase-0-foundations/`](phase-0-foundations/spec.md) | remaining spikes and human-only setup | now |
| [`phase-1-capture-engine/`](phase-1-capture-engine/spec.md) | model, capture engine, renderer, golden fixtures | after the Phase 0 spikes |

Phase 3 (iPhone app) and Phase 2 (Chrome/Edge) get their own folders once Phase 1 is under way (ADR-0011).

To find the next item, look for files with `Status: ready-for-agent` (or `ready-for-human`) whose `Blocked by:` tickets are all `resolved`. Take them lowest-numbered first.
