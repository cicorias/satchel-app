# Capture: page pipeline and Turndown rules

Status: needs-info
Type: task
Blocked by: 04, ../../phase-0-foundations/issues/02

Spec §4.4 steps 1–8 and §4.5 conventions: clone the DOM, preprocess lazy images, extract with Defuddle, postprocess, convert with Turndown plus our rules, collect `ImageRef`s, assemble frontmatter (§5), and apply the guardrails. Pin `defuddle` and `turndown` exactly.

This is `needs-info` until Spike C (phase-0 ticket 02) decides whether we reuse Defuddle's Turndown setup.
