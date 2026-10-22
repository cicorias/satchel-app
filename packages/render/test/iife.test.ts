// The IIFE bundle in a plain-script context: evaluated inside a jsdom window, as a <script> tag would be.

import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { expect, test } from 'vitest';

const bundle = readFileSync(new URL('../dist/render.iife.js', import.meta.url), 'utf8');

test('render.iife.js exposes the full API on globalThis.SatchelRender', () => {
  const dom = new JSDOM('<!doctype html><html><body></body></html>', { runScripts: 'outside-only' });
  dom.window.eval(bundle);
  const api = (dom.window as unknown as { SatchelRender: Record<string, unknown> }).SatchelRender;

  expect(Object.keys(api).sort()).toEqual(['createRenderer', 'render', 'splitFrontmatter', 'version']);
  const render = api.render as (md: string) => { html: string; frontmatter: string | null };
  const result = render('---\ntitle: "x"\n---\n\n# Hello\n\n<img src=x onerror=alert(1)> **safe**');
  expect(result.frontmatter).toBe('title: "x"');
  expect(result.html).toContain('<h1');
  expect(result.html).toContain('<strong>safe</strong>');
  expect(result.html).not.toMatch(/onerror|<script/i);
});
