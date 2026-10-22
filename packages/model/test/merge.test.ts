import { describe, expect, test } from 'vitest';
import { type Item, mergeItems } from '../src/index.ts';

const ID = 'u_445740458d1bf9f96939cbc420e6973c';

function item(overrides: Partial<Item> & Record<string, unknown> = {}): Item {
  return {
    schemaVersion: 1,
    id: ID,
    kind: 'link',
    url: 'https://example.com/articles/hello-world',
    canonicalUrl: 'https://example.com/articles/hello-world',
    normalizedUrl: 'https://example.com/articles/hello-world',
    title: 'Hello, World',
    tags: [],
    createdAt: '2026-10-01T00:00:00.000Z',
    updatedAt: '2026-10-01T00:00:00.000Z',
    metadataStatus: 'complete',
    source: { client: 'chrome', version: '2026.10.0' },
    ...overrides,
  } as Item;
}

const page = (capturedAt: string, engine: string, overrides: Partial<Item> = {}) =>
  item({
    kind: 'page',
    capturedAt,
    updatedAt: capturedAt,
    page: { wordCount: 100, readingMinutes: 1, engine, images: [] },
    ...overrides,
  });

const older = '2026-10-01T00:00:00.000Z';
const newer = '2026-10-05T00:00:00.000Z';

describe('mergeItems (§7.3)', () => {
  test('refuses to merge different IDs', () => {
    expect(() => mergeItems(item(), item({ id: 'u_00000000000000000000000000000000' }))).toThrow();
  });

  test('createdAt: earliest wins', () => {
    const { item: merged } = mergeItems(
      item({ createdAt: newer, updatedAt: newer }),
      item({ createdAt: older, updatedAt: older }),
    );
    expect(merged.createdAt).toBe(older);
  });

  test('createdAt compares instants, not strings', () => {
    const { item: merged } = mergeItems(item({ createdAt: '2026-10-01T05:00:00+05:00' }), item({ createdAt: older }));
    expect(merged.createdAt).toBe('2026-10-01T05:00:00+05:00');
  });

  test('updatedAt: latest wins', () => {
    expect(mergeItems(item({ updatedAt: older }), item({ updatedAt: newer })).item.updatedAt).toBe(newer);
  });

  test.each([
    ['link', 'link', 'link'],
    ['link', 'page', 'page'],
    ['page', 'link', 'page'],
    ['page', 'page', 'page'],
  ] as const)('kind: %s + %s = %s', (x, y, expected) => {
    const a = x === 'page' ? page(older, 'e1') : item({ updatedAt: older });
    const b = y === 'page' ? page(newer, 'e2') : item({ updatedAt: newer });
    expect(mergeItems(a, b).item.kind).toBe(expected);
  });

  test('tags: union, deduplicated, keeping the existing order and appending new tags', () => {
    const a = item({ updatedAt: older, tags: ['swift', 'ios'] });
    const b = item({ updatedAt: newer, tags: ['web', 'ios'] });
    expect(mergeItems(a, b).item.tags).toEqual(['swift', 'ios', 'web']);
    expect(mergeItems(b, a).item.tags).toEqual(['swift', 'ios', 'web']);
  });

  describe('note: most recently updated wins', () => {
    test('the newer note replaces the older one', () => {
      const a = item({ updatedAt: older, note: 'first' });
      const b = item({ updatedAt: newer, note: 'second' });
      expect(mergeItems(a, b).item.note).toBe('second');
    });

    test('a newer save without a note keeps the existing note', () => {
      const a = item({ updatedAt: older, note: 'keep me' });
      const b = item({ updatedAt: newer });
      expect(mergeItems(a, b).item.note).toBe('keep me');
    });

    test('a newer empty note clears it', () => {
      const a = item({ updatedAt: older, note: 'old' });
      const b = item({ updatedAt: newer, note: '' });
      expect(mergeItems(a, b).item.note).toBe('');
    });

    test('no note on either side stays absent', () => {
      expect('note' in mergeItems(item(), item({ updatedAt: newer })).item).toBe(false);
    });
  });

  describe('metadata: the newer capture wins, but never with an empty value', () => {
    test('a newer non-empty value replaces the older one', () => {
      const a = item({ updatedAt: older, title: 'Old title', description: 'Old description' });
      const b = item({ updatedAt: newer, title: 'New title', description: 'New description' });
      expect(mergeItems(a, b).item).toMatchObject({ title: 'New title', description: 'New description' });
    });

    test.each(['title', 'description', 'siteName', 'author', 'imageUrl', 'faviconUrl', 'lang', 'publishedAt'] as const)(
      'an empty or missing %s never overwrites a value',
      (field) => {
        const value = field === 'publishedAt' ? '2026-09-30T12:00:00.000Z' : `old ${field}`;
        const a = item({ updatedAt: older, [field]: value });
        expect(mergeItems(a, item({ updatedAt: newer, [field]: '' })).item[field]).toBe(value);
        expect(mergeItems(a, item({ updatedAt: newer, [field]: '   ' })).item[field]).toBe(value);
        const missing = item({ updatedAt: newer });
        delete (missing as Partial<Item>)[field];
        expect(mergeItems(a, missing).item[field]).toBe(value);
      },
    );

    test('page captures are ordered by capturedAt, not updatedAt', () => {
      // `a` was captured later but edited (tagged) after `b` was captured.
      const a = page('2026-10-04T00:00:00.000Z', 'e1', {
        title: 'Captured later',
        updatedAt: '2026-10-09T00:00:00.000Z',
      });
      const b = page('2026-10-02T00:00:00.000Z', 'e2', {
        title: 'Captured earlier',
        updatedAt: '2026-10-03T00:00:00.000Z',
      });
      expect(mergeItems(a, b).item.title).toBe('Captured later');
    });

    test('source comes from the newer capture', () => {
      const a = item({ updatedAt: older, source: { client: 'chrome', version: '2026.10.0' } });
      const b = item({ updatedAt: newer, source: { client: 'ios-share', version: '2026.10.1' } });
      expect(mergeItems(a, b).item.source).toEqual({ client: 'ios-share', version: '2026.10.1' });
    });

    test('metadataStatus keeps the best of complete > pending > failed', () => {
      const status = (x: Item['metadataStatus'], y: Item['metadataStatus']) =>
        mergeItems(item({ metadataStatus: x, updatedAt: older }), item({ metadataStatus: y, updatedAt: newer })).item
          .metadataStatus;
      expect(status('complete', 'pending')).toBe('complete');
      expect(status('failed', 'pending')).toBe('pending');
      expect(status('failed', 'complete')).toBe('complete');
      expect(status('failed', 'failed')).toBe('failed');
    });
  });

  describe('body: the newer page capture wins', () => {
    test('two pages: the newer capture keeps its body and page info, and the UI should ask first', () => {
      const result = mergeItems(page(older, 'old-engine'), page(newer, 'new-engine'));
      expect(result.body).toBe('b');
      expect(result.replacesBody).toBe(true);
      expect(result.item.page?.engine).toBe('new-engine');
      expect(result.item.capturedAt).toBe(newer);
    });

    test('a newer link save keeps the existing page body without asking', () => {
      const result = mergeItems(page(older, 'e1', { selection: true }), item({ updatedAt: newer, title: 'Newer' }));
      expect(result).toMatchObject({ body: 'a', replacesBody: false });
      expect(result.item).toMatchObject({ kind: 'page', capturedAt: older, selection: true, title: 'Newer' });
      expect(result.item.page?.engine).toBe('e1');
    });

    test('two links have no body', () => {
      const result = mergeItems(item(), item({ updatedAt: newer }));
      expect(result).toMatchObject({ body: 'none', replacesBody: false });
      expect('page' in result.item || 'capturedAt' in result.item).toBe(false);
    });

    test('selection travels with the winning body', () => {
      const a = page(older, 'e1', { selection: true });
      const b = page(newer, 'e2');
      expect('selection' in mergeItems(a, b).item).toBe(false);
    });
  });

  test('unknown fields from either side survive, the newer capture winning a clash', () => {
    const a = item({ updatedAt: older, archived: true, color: 'red' });
    const b = item({ updatedAt: newer, color: 'blue', pinned: 1 });
    expect(mergeItems(a, b).item).toMatchObject({ archived: true, color: 'blue', pinned: 1 });
  });

  test('does not mutate its inputs', () => {
    const a = page(older, 'e1', { tags: ['b'], note: 'x' });
    const b = item({ updatedAt: newer, tags: ['a'] });
    const snapshot = JSON.stringify([a, b]);
    mergeItems(a, b);
    expect(JSON.stringify([a, b])).toBe(snapshot);
  });
});

describe('commutativity: both devices converge', () => {
  const samples: Item[] = [
    item(),
    item({ updatedAt: newer, title: 'Renamed', tags: ['x'], note: 'n1' }),
    item({ createdAt: '2026-09-01T00:00:00.000Z', updatedAt: older, description: 'Described', tags: ['y', 'x'] }),
    page(older, 'e1', { note: '', metadataStatus: 'pending', author: 'A. Writer' }),
    page(newer, 'e2', { selection: true, source: { client: 'safari-ios', version: '2026.10.0' } }),
    page(newer, 'e3', { title: 'Same instant, different capture' }),
    item({ updatedAt: newer, metadataStatus: 'failed', extra: { nested: true } } as Partial<Item>),
  ];
  const pairs = samples.flatMap((a, i) => samples.slice(i + 1).map((b) => [i, samples.indexOf(b), a, b] as const));

  test.each(pairs)('merge(#%i, #%i) = merge(#%i reversed)', (_, __, a, b) => {
    const ab = mergeItems(a, b);
    const ba = mergeItems(b, a);
    expect(ab.item).toStrictEqual(ba.item);
    expect(ab.replacesBody).toBe(ba.replacesBody);
    expect(ab.body === 'none' ? 'none' : ab.body === 'a' ? a : b).toBe(
      ba.body === 'none' ? 'none' : ba.body === 'a' ? b : a,
    );
  });

  test('merging an item with itself returns the same item', () => {
    for (const sample of samples) expect(mergeItems(sample, sample).item).toStrictEqual(sample);
  });
});
