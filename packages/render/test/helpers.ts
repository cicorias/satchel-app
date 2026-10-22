// Shared test DOM (jsdom: DOMPurify's documented Node environment) and an independent safety check of rendered HTML.

import { JSDOM } from 'jsdom';
import { expect } from 'vitest';
import { createRenderer, type RendererInit, type WindowLike } from '../src/index.ts';

export const dom = new JSDOM('<!doctype html><html><body></body></html>');
export const testWindow = dom.window as unknown as WindowLike;

export const renderer = (init: Omit<RendererInit, 'window'> = {}) => createRenderer({ window: testWindow, ...init });

/** Parses `html` the way a host inserting it with innerHTML would. */
export function parse(html: string): HTMLElement {
  const div = dom.window.document.createElement('div');
  div.innerHTML = html;
  return div;
}

// Written out here rather than imported, so a mistake in the sanitizer's allowlist can't hide from the tests.
const SAFE_TAGS = new Set(
  (
    'a abbr b blockquote br caption cite code col colgroup dd del details dfn div dl dt em figcaption figure ' +
    'h1 h2 h3 h4 h5 h6 hr i img input ins kbd li mark ol p pre q s samp section small span strong sub summary sup ' +
    'table tbody td tfoot th thead time tr u ul var wbr'
  ).split(' '),
);
const SAFE_ATTRS = new Set(
  (
    'align alt checked class colspan data-callout datetime decoding disabled height href id loading open ' +
    'referrerpolicy rel reversed rowspan scope span src start target title type width'
  ).split(' '),
);

/** Fails unless every element, attribute, and URL in `html` is on the safe lists, and re-parsing is stable (mXSS). */
export function expectSafe(html: string): void {
  const root = parse(html);
  for (const el of Array.from(root.querySelectorAll('*'))) {
    const tag = el.tagName.toLowerCase();
    expect(SAFE_TAGS.has(tag), `tag <${tag}> in ${html}`).toBe(true);
    expect(el.namespaceURI).toBe('http://www.w3.org/1999/xhtml');
    for (const name of el.getAttributeNames()) {
      expect(SAFE_ATTRS.has(name), `attribute ${name} on <${tag}> in ${html}`).toBe(true);
    }
    const href = el.getAttribute('href');
    if (href !== null) expect(href, html).toMatch(/^(?:https?:|mailto:|tel:|#)/i);
    const src = el.getAttribute('src');
    if (src !== null)
      expect(src, html).toMatch(/^(?:https?:|blob:|data:image\/(?:png|jpe?g|gif|webp|avif|bmp|svg\+xml)[;,])/i);
    if (tag === 'input') {
      expect(el.getAttribute('type')).toBe('checkbox');
      expect(el.hasAttribute('disabled')).toBe(true);
    }
  }
  expect(html).not.toMatch(
    /<\/?(?:script|style|iframe|object|embed|form|svg|math|template|noscript|base|meta|link)\b/i,
  );
  // Serializing and re-parsing must not change the tree (mutation XSS).
  const once = root.innerHTML;
  expect(parse(once).innerHTML).toBe(once);
}
