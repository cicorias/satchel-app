# ADR-0009: Images — references first, stored assets later, Base64 only on export

- **Status:** Accepted
- **Date:** 2026-10-21

**Context.** Initially, saved pages should reference images by URL. Later, pages should be fully self-contained.

**Decision.**
- Phases 1–4: store absolute remote image URLs.
- Phase 5: download images and store them as provider assets; rewrite Markdown to relative `images/<hash>.<ext>` paths.
- Generate Base64 data URIs only for the "self-contained export" option, never as the stored format.

**Reasons.**
- Base64 inflates image size by about a third, makes Markdown unreadable and hard to edit, pushes CloudKit records past their 1 MB limit, and prevents deduplication of shared images.
- Relative image paths are what Obsidian and other Markdown editors expect.
- Remote references rot: CDN URLs expire and sites block hotlinking. Phase 5 should therefore not be postponed indefinitely, and images should be fetched soon after capture by the capturing client, which has the right cookies and referrer.
