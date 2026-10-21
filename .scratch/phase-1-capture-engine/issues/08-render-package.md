# Render: markdown-it + DOMPurify

Status: ready-for-agent
Type: task
Blocked by: -

Spec §9.1.4 and §11: render Markdown (including frontmatter handling, footnotes, and callouts) to sanitized HTML, with no scripts, iframes, or event handlers, and a remote-image toggle. Build both ESM and IIFE (`globalThis.SatchelRender`).

**Done when** unit tests include XSS payloads that are neutralized.
