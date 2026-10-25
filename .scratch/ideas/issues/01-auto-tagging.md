# Auto-tagging spike

Status: needs-triage
Type: research
Blocked by: -

Suggest tags for link and page saves, and optionally apply them in the background, with everything running on-device. Expanded from idea 1 on 2026-10-25.

## Behavior

- **At save:** up to 5 suggested tags appear as chips in the save sheet or popup. Tapping a chip accepts it. One-tap save without tags still works (FR-5).
- **Background auto-tagging:** a toggle in the save sheet, on by default, that remembers the last choice on each device. When it's on, tags are applied after the save. This covers anything you didn't decide at save time.
- **Vocabulary:** prefer your existing tags, and allow 1–2 new ones, visually marked as new.
- **Provenance:** store which tags were auto-applied (a spec §7 data-model change). The UI shows them subtly and supports "accept all" and bulk removal.
- **Input text:**
  - At save, a link is tagged from its metadata: title, description, site name, URL path.
  - In the background, the page is fetched and its body is used too. A page save uses its body in both cases.
- **Backfill:** a run over items saved before auto-tagging existed, in the host app.

## Scope

- **In:** the iPhone app, the Share Extension, the Safari extension's save sheet (through native code), and backfilling the existing library.
- **Out for now:** Chrome and Edge (they'd need a different engine), and cloud models. The setting is on-device only (ADR-0006).

## Engines to compare

1. Apple Foundation Models: guided generation; check device support and whether it fits the Share Extension's memory budget.
2. NaturalLanguage embeddings: score the content against each existing tag.
3. Keyword extraction: NLTagger nouns and named entities, plus TF-IDF over the body. These are the candidates for new tags.
4. Site and domain rules, learned from your history (for example, github.com → `code`).

A combination is a valid outcome, for example rules and embeddings for existing tags plus keywords for new ones.

## How to judge

- **Test set:** about 50 items from your library. Hide their tags, run each engine, and score how many of your tags it recovers. You review its new-tag suggestions by eye.
- **Also report:** latency and peak memory in the Share Extension and the Safari extension handler, and which devices each engine supports. Mark which engines can run within the extension's time budget, and which have to run in the background in the host app.

## Answer

(The spike writes its recommendation here. If the outcome changes the data model or the product, it becomes an ADR.)

## Comments
