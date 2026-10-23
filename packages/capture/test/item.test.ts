import { itemIdFor, UnsupportedUrlError } from '@satchel/model';
import { parseHTML } from 'linkedom';
import { describe, expect, test } from 'vitest';
import { captureLink, capturePage, itemFromCapture, normalizeTags } from '../src/index.ts';

const PAGE = 'https://www.example.com/posts/kayak?utm_source=feed';
const NOW = new Date('2026-10-22T12:00:00.000Z');
const PROSE = Array.from(
  { length: 8 },
  (_, i) => `<p>Paragraph ${i + 1} explains how the river trip went and what we would pack next time.</p>`,
).join('');

const doc = () =>
  parseHTML(`<!doctype html><html lang="en"><head><title>Kayaking the Upper River</title>
    <link rel="canonical" href="https://example.com/posts/kayak">
    <meta name="description" content="  A river trip.  "><meta name="author" content="Ann Lee">
    </head><body><article><h1>Kayaking the Upper River</h1>${PROSE}</article></body></html>`)
    .document as unknown as Document;

describe('itemFromCapture', () => {
  test('a link capture becomes a link Item with no body', () => {
    const capture = captureLink(doc(), { pageUrl: PAGE });
    const { item, body } = itemFromCapture(capture, {
      pageUrl: PAGE,
      client: 'safari-ios',
      version: '2026.10.0',
      tags: [' Rivers ', 'gear', 'rivers', ''],
      note: '  pack lighter  ',
      now: NOW,
    });

    expect(body).toBeUndefined();
    expect(item).toMatchObject({
      schemaVersion: 1,
      id: itemIdFor('https://example.com/posts/kayak'),
      kind: 'link',
      url: PAGE,
      canonicalUrl: 'https://example.com/posts/kayak',
      normalizedUrl: 'https://example.com/posts/kayak',
      title: 'Kayaking the Upper River',
      description: 'A river trip.',
      author: 'Ann Lee',
      lang: 'en',
      tags: ['rivers', 'gear'],
      note: 'pack lighter',
      createdAt: '2026-10-22T12:00:00.000Z',
      updatedAt: '2026-10-22T12:00:00.000Z',
      metadataStatus: 'complete',
      source: { client: 'safari-ios', version: '2026.10.0' },
    });
    expect(item).not.toHaveProperty('page');
    expect(item).not.toHaveProperty('capturedAt');
    expect(item).not.toHaveProperty('selection');
  });

  test('a page capture becomes a page Item whose body has no frontmatter', async () => {
    const capture = await capturePage(doc(), { pageUrl: PAGE, now: NOW });
    const { item, body } = itemFromCapture(capture, {
      pageUrl: PAGE,
      client: 'safari-ios',
      version: '2026.10.0',
      now: NOW,
    });

    expect(item.kind).toBe('page');
    expect(item.capturedAt).toBe('2026-10-22T12:00:00.000Z');
    expect(item.page).toEqual({
      wordCount: capture.stats.wordCount,
      readingMinutes: capture.stats.readingMinutes,
      engine: `${capture.engine.extractor} + ${capture.engine.converter}`,
      images: [],
    });
    expect(body).toBe(capture.bodyMarkdown);
    expect(body?.startsWith('# Kayaking the Upper River\n')).toBe(true);
    expect(item).not.toHaveProperty('note');
  });

  test('marks a selection and falls back to the URL for a missing title', () => {
    const capture = captureLink(doc(), { pageUrl: PAGE });
    capture.metadata.title = '   ';
    const { item } = itemFromCapture(capture, { pageUrl: PAGE, client: 'chrome', version: '1', selection: true });
    expect(item.selection).toBe(true);
    expect(item.title).toBe(PAGE);
  });

  test('rejects a non-web URL', () => {
    const capture = captureLink(doc(), { pageUrl: PAGE });
    capture.metadata.canonicalUrl = 'file:///tmp/a.html';
    expect(() => itemFromCapture(capture, { pageUrl: 'file:///tmp/a.html', client: 'chrome', version: '1' })).toThrow(
      UnsupportedUrlError,
    );
  });
});

test('normalizeTags lowercases, trims, and deduplicates in order', () => {
  expect(normalizeTags(['B', ' a ', 'b', '  '])).toEqual(['b', 'a']);
});
