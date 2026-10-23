// The IIFE bundle (spec §4.1) in a plain-script context: a fresh global with only browser-like globals from
// linkedom, as in the Share Extension preprocessing script or a WKWebView. Turbo builds it before tests run.

import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import { parseHTML } from 'linkedom';
import { expect, test } from 'vitest';

const bundle = readFileSync(new URL('../dist/capture.iife.js', import.meta.url), 'utf8');
const html = `<!doctype html><html lang="en"><head><title>Script context</title>
  <meta property="og:title" content="Loaded from a script tag"></head>
  <body><article><h1>Loaded from a script tag</h1>${'<p>The bundle runs with nothing but the globals a page would give it, and still extracts this article.</p>'.repeat(6)}</article></body></html>`;

test('capture.iife.js exposes the full API on globalThis.SatchelCapture', async () => {
  const { window, document, DOMParser } = parseHTML(html);
  const sandbox: Record<string, unknown> = { window, document, DOMParser, console, URL, TextEncoder };
  sandbox.globalThis = sandbox;
  const context = createContext(sandbox);
  runInContext(bundle, context);
  const api = sandbox.SatchelCapture as Record<string, unknown>;

  expect(Object.keys(api).sort()).toEqual(
    [
      'ENGINE',
      'MAX_MARKDOWN_BYTES',
      'PageTooLargeError',
      'captureLink',
      'capturePage',
      'collectImages',
      'countWords',
      'extractMetadata',
      'formatFrontmatter',
      'htmlToMarkdown',
      'itemFromCapture',
      'normalizeTags',
      'readingStats',
      'version',
    ].sort(),
  );

  const doc = runInContext('document', context) as Document;
  const link = (api.captureLink as (d: Document, o: object) => { metadata: { title: string } })(doc, {
    pageUrl: 'https://example.com/a',
  });
  expect(link.metadata.title).toBe('Loaded from a script tag');

  const page = await (api.capturePage as (d: Document, o: object) => Promise<{ bodyMarkdown: string }>)(doc, {
    pageUrl: 'https://example.com/a',
  });
  expect(page.bodyMarkdown).toMatch(/^# Loaded from a script tag\n\nThe bundle runs/);
});
