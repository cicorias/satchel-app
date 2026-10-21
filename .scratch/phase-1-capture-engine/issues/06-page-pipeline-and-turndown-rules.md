# Capture: page pipeline and Turndown rules

Status: ready-for-agent
Type: task
Blocked by: 04, ../../phase-0-foundations/issues/02

Spec §4.4 steps 1–8 and §4.5 conventions: clone the DOM, preprocess lazy images, extract with Defuddle, postprocess, convert with Turndown plus our rules, collect `ImageRef`s, assemble frontmatter (§5), and apply the guardrails. Pin `defuddle` and `turndown` exactly.

Spike C has decided (ADR-0003 addendum): **port** Defuddle 0.19.4's `src/markdown.ts` rules into `packages/capture/src/markdown/`, using our own `turndown@7.2.4` and no GFM plugin. Keep the MIT header and update `THIRD_PARTY_NOTICES.md`. Call Defuddle with **`useAsync: false`**. Otherwise it can fetch page content from third-party services, which violates ADR-0006 and §3.2. The addendum lists the §4.5 changes to make to the ported rules and the Defuddle behaviors to decide on. Port the 0.19.5 escaping fixes once that version is eligible (2026-10-24).
