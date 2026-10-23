// A capture → the Item it saves (spec §7.1). Shared by every surface that captures in JavaScript: the extension
// popup on all three browsers and the Share Extension's preprocessing script.

import type { ClientId, Item } from '@satchel/model';
import { itemIdFor, normalizedUrlFor, SCHEMA_VERSION } from '@satchel/model';
import type { LinkCapture, PageCapture } from './types.ts';

export interface ItemOptions {
  /** The document's URL, as passed to `captureLink`/`capturePage`. */
  pageUrl: string;
  client: ClientId;
  /** The app version (CalVer). */
  version: string;
  tags?: string[];
  note?: string;
  /** The capture was a selection (FR-10). */
  selection?: boolean;
  now?: Date;
}

export interface CapturedItem {
  item: Item;
  /** A page's Markdown without frontmatter (`PageCapture.bodyMarkdown`). Frontmatter is generated from the Item
   * on export, so it never goes stale (spec §5). Absent for a link. */
  body?: string;
}

/** Lowercased, trimmed, deduplicated, in the order given. */
export function normalizeTags(tags: readonly string[]): string[] {
  return [...new Set(tags.map((tag) => tag.trim().toLowerCase()).filter((tag) => tag !== ''))];
}

const nonBlank = (value: string | undefined) => {
  const trimmed = value?.trim();
  return trimmed ? trimmed : undefined;
};

/** Builds the Item a capture saves: a page when `capture` has Markdown, otherwise a link. Throws
 * `UnsupportedUrlError` for a non-http(s) `pageUrl`. */
export function itemFromCapture(capture: LinkCapture | PageCapture, opts: ItemOptions): CapturedItem {
  const { metadata } = capture;
  const now = (opts.now ?? new Date()).toISOString();
  const normalizedUrl = normalizedUrlFor(opts.pageUrl, metadata.canonicalUrl);
  const page = 'bodyMarkdown' in capture ? capture : undefined;

  const item: Item = {
    schemaVersion: SCHEMA_VERSION,
    id: itemIdFor(normalizedUrl),
    kind: page ? 'page' : 'link',
    url: opts.pageUrl,
    canonicalUrl: metadata.canonicalUrl,
    normalizedUrl,
    title: nonBlank(metadata.title) ?? opts.pageUrl,
    tags: normalizeTags(opts.tags ?? []),
    createdAt: now,
    updatedAt: now,
    metadataStatus: 'complete',
    source: { client: opts.client, version: opts.version },
  };
  const optional = {
    description: nonBlank(metadata.description),
    siteName: nonBlank(metadata.siteName),
    author: nonBlank(metadata.author),
    publishedAt: nonBlank(metadata.publishedAt),
    imageUrl: nonBlank(metadata.imageUrl),
    faviconUrl: nonBlank(metadata.faviconUrl),
    lang: nonBlank(metadata.lang),
    note: nonBlank(opts.note),
  };
  for (const [key, value] of Object.entries(optional)) {
    if (value !== undefined) Object.assign(item, { [key]: value });
  }
  if (opts.selection) item.selection = true;
  if (!page) return { item };

  item.capturedAt = now;
  item.page = {
    wordCount: page.stats.wordCount,
    readingMinutes: page.stats.readingMinutes,
    engine: `${page.engine.extractor} + ${page.engine.converter}`,
    images: page.images,
  };
  return { item, body: page.bodyMarkdown };
}
