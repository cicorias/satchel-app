# Spike C: Defuddle's Markdown extension points

Status: resolved
Type: research
Blocked by: -

ADR-0003 implementation note. Find out whether Defuddle's full bundle exposes its Turndown instance or its rules, so we can extend them with our own rules and inherit its callout, footnote, and math handling.

## Do

- Install `defuddle` at an exact version that passes pnpm's minimum-release-age check, in a throwaway branch or scratch package.
- Inspect its exports, both the full bundle and `defuddle/node`. Check whether there's a Turndown instance, a rules export, or a `markdown` option hook.
- Find out whether `turndown-plugin-gfm` is maintained, or whether to use `@joplin/turndown-plugin-gfm` or port the rules (spec §4.5 VERIFY).

## Done when

- An addendum to ADR-0003 records: reuse Defuddle's Turndown, or instantiate our own and port the rules. It also records which GFM plugin to use, with exact versions.

## Answer

2026-10-21. **Port Defuddle's rules into our own Turndown; don't reuse Defuddle's converter, and add no GFM plugin.**
- Pins: `defuddle@0.19.4` (extraction only, `useAsync: false`), `turndown@7.2.4`, `@types/turndown@5.0.6`, `linkedom@0.18.12`.
- Full findings: `../research/02-spike-c-defuddle-markdown.md`. The decision is in the ADR-0003 addendum.
- This unblocks `phase-1-capture-engine/issues/06`.
