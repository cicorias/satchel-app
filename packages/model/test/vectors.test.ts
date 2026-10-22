// Shared vectors for other languages (Phase 3 ticket 03): the model's own outputs, written to fixtures/model/vectors/
// and checked here on every run. SatchelKit's tests check that its JavaScriptCore bridge returns the same values.
// `UPDATE_VECTORS=1 pnpm --filter @satchel/model test` rewrites them after an intended behavior change.

import { readFileSync, writeFileSync } from 'node:fs';
import { expect, test } from 'vitest';
import { type Item, itemIdFor, mergeItems, normalizedUrlFor } from '../src/index.ts';

const dir = new URL('../../../fixtures/model/', import.meta.url);
const UPDATE = process.env.UPDATE_VECTORS === '1';

function check(name: string, value: unknown) {
  const path = new URL(`vectors/${name}`, dir);
  const json = `${JSON.stringify(value, null, 2)}\n`;
  if (UPDATE) writeFileSync(path, json);
  else expect(json).toBe(readFileSync(path, 'utf8'));
}

test('normalization and ID vectors', () => {
  const inputs: [string, string | null][] = JSON.parse(
    readFileSync(new URL('url-inputs.json', import.meta.url), 'utf8'),
  );
  check(
    'normalization.json',
    inputs.map(([pageUrl, canonicalUrl]) => {
      try {
        const normalizedUrl = normalizedUrlFor(pageUrl, canonicalUrl ?? undefined);
        return { pageUrl, canonicalUrl, normalizedUrl, id: itemIdFor(normalizedUrl) };
      } catch (error) {
        return { pageUrl, canonicalUrl, error: (error as Error).name };
      }
    }),
  );
});

test('merge vectors', () => {
  const fixture = (name: string): Item => JSON.parse(readFileSync(new URL(name, dir), 'utf8'));
  const link = fixture('link-minimal.json');
  const later = (item: Item, overrides: Partial<Item> & Record<string, unknown>): Item =>
    ({ ...item, ...overrides }) as Item;
  const page = later(link, {
    kind: 'page',
    title: 'Hello, World: the page',
    capturedAt: '2026-10-23T09:00:00.000Z',
    updatedAt: '2026-10-23T09:00:00.000Z',
    metadataStatus: 'complete',
    source: { client: 'safari-ios', version: '2026.10.0' },
    page: { wordCount: 900, readingMinutes: 4, engine: 'defuddle@0.19.4+turndown@7.2.4', images: [] },
  });
  const pairs: [string, Item, Item][] = [
    [
      'link re-saved with tags and a note',
      link,
      later(link, { tags: ['swift'], note: 'read later', updatedAt: '2026-10-22T15:00:00.000Z' }),
    ],
    ['link upgraded to a page', link, page],
    [
      'page re-captured',
      page,
      later(page, {
        capturedAt: '2026-10-24T08:00:00.000Z',
        updatedAt: '2026-10-24T08:00:00.000Z',
        title: 'Hello again',
      }),
    ],
    [
      'newer save with empty metadata keeps values',
      page,
      later(link, { title: '', updatedAt: '2026-10-25T00:00:00.000Z' }),
    ],
    [
      'unknown fields from both sides',
      later(link, { archived: true }),
      later(link, { pinned: 1, updatedAt: '2026-10-22T16:00:00.000Z' }),
    ],
  ];
  check(
    'merge.json',
    pairs.map(([name, a, b]) => ({ name, a, b, result: mergeItems(a, b) })),
  );
});
