# Capture: metadata resolver (data islands)

Status: ready-for-agent
Type: task
Blocked by: 01

Spec §4.2: `extractMetadata(doc, pageUrl)` with the per-field priority table, JSON-LD rules (invalid JSON → a warning, flattening `@graph`, preferred `@type`s), URL absolutization respecting `<base href>`, and the normalization and truncation rules. Implement `captureLink` on top of it.

**Done when** unit tests with linkedom cover each field's fallback chain, and the first golden fixtures (ticket 07) pass for link mode.
