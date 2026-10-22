// Metadata resolution from "data islands" (spec §4.2): <head> tags and JSON-LD only, the fast path for link
// mode. Each field takes the first non-empty source in the §4.2 priority order.

import { linkExcerpt } from './excerpt.ts';
import { type JsonLd, readJsonLd, typesOf } from './json-ld.ts';
import { absoluteHttpUrl, clean, isoDate, truncate } from './text.ts';

export interface PageMetadata {
  title: string;
  description?: string;
  siteName: string;
  canonicalUrl: string;
  imageUrl?: string;
  author?: string;
  publishedAt?: string;
  faviconUrl: string;
  lang?: string;
  type?: string;
}

export interface MetadataResult {
  metadata: PageMetadata;
  warnings: string[];
}

const first = <T>(...values: (T | undefined)[]): T | undefined => values.find((value) => value !== undefined);

/**
 * `<meta>` content keyed by lowercase `property` or `name` (sites mix them up for og:/twitter: tags).
 * The first tag for a key wins. The whole document is searched because malformed markup can leave head
 * tags in the body after parsing.
 */
function readMeta(doc: Document): Map<string, string> {
  const meta = new Map<string, string>();
  for (const tag of doc.querySelectorAll('meta[content]')) {
    const content = tag.getAttribute('content') ?? '';
    for (const attr of ['property', 'name']) {
      const key = tag.getAttribute(attr)?.trim().toLowerCase();
      if (key && content.trim() !== '' && !meta.has(key)) meta.set(key, content);
    }
  }
  return meta;
}

const relTokens = (link: Element) => (link.getAttribute('rel') ?? '').toLowerCase().split(/\s+/);

/** The largest edge in a `sizes` attribute; `any` (scalable icons) beats every fixed size. */
function iconSize(link: Element): number {
  const sizes = (link.getAttribute('sizes') ?? '').toLowerCase();
  if (sizes.split(/\s+/).includes('any')) return Number.POSITIVE_INFINITY;
  let largest = 0;
  for (const match of sizes.matchAll(/(\d+)x(\d+)/g)) largest = Math.max(largest, Number(match[1]), Number(match[2]));
  return largest;
}

function largestIcon(doc: Document, rels: string[], base: string): string | undefined {
  let best: { url: string; size: number } | undefined;
  for (const link of doc.querySelectorAll('link[rel][href]')) {
    if (!relTokens(link).some((token) => rels.includes(token))) continue;
    const url = absoluteHttpUrl(link.getAttribute('href')?.trim(), base);
    const size = iconSize(link);
    if (url && (best === undefined || size > best.size)) best = { url, size };
  }
  return best?.url;
}

/** A string, an object's `.url` (or `@id` reference to one), or the first entry of an array of either. */
function jsonLdImage(ld: JsonLd, value: unknown): unknown {
  const image = ld.resolve(Array.isArray(value) ? value[0] : value);
  if (typeof image === 'string') return image;
  if (typeof image === 'object' && image !== null) return (image as Record<string, unknown>).url;
  return undefined;
}

function jsonLdNames(doc: Document, ld: JsonLd, value: unknown): string | undefined {
  const names = (Array.isArray(value) ? value : [value])
    .map((entry) => {
      const resolved = ld.resolve(entry);
      return clean(
        doc,
        typeof resolved === 'object' && resolved !== null ? (resolved as { name?: unknown }).name : resolved,
      );
    })
    .filter((name): name is string => name !== undefined);
  return names.length > 0 ? [...new Set(names)].join(', ') : undefined;
}

const looksLikeUrl = (value: string | undefined) => value !== undefined && /^https?:\/\//i.test(value);

export interface MetadataOptions {
  /**
   * End the description chain with the link-mode body excerpt (§4.3). Page mode turns this off and uses
   * Defuddle's description and its own excerpt from the extracted content instead.
   */
  bodyExcerpt?: boolean;
}

export function extractMetadata(doc: Document, pageUrl: string, options: MetadataOptions = {}): MetadataResult {
  const warnings: string[] = [];
  const page = new URL(pageUrl);
  const base = absoluteHttpUrl(doc.querySelector('base[href]')?.getAttribute('href')?.trim(), pageUrl) ?? pageUrl;
  const meta = readMeta(doc);
  const tag = (key: string) => clean(doc, meta.get(key));
  const ld = readJsonLd(doc, warnings);
  const node = ld.primary ?? {};
  const field = (key: string) => clean(doc, node[key]);
  const publisher = ld.resolve(node.publisher) as Record<string, unknown> | undefined;

  const hostname = page.hostname.replace(/^www\./, '');
  const path = page.pathname === '/' ? '' : page.pathname;

  const title =
    first(
      tag('og:title'),
      tag('twitter:title'),
      field('headline'),
      field('name'),
      clean(doc, doc.querySelector('title')?.textContent),
    ) ?? `${page.hostname}${path}`;

  const description = first(
    tag('og:description'),
    tag('twitter:description'),
    tag('description'),
    field('description'),
    options.bodyExcerpt === false ? undefined : linkExcerpt(doc),
  );

  const siteName = first(tag('og:site_name'), clean(doc, publisher?.name), tag('application-name')) ?? hostname;

  const canonicalUrl =
    first(
      absoluteHttpUrl(doc.querySelector('link[rel~="canonical" i][href]')?.getAttribute('href')?.trim(), base),
      absoluteHttpUrl(tag('og:url'), base),
    ) ?? pageUrl;

  const imageUrl = first(
    absoluteHttpUrl(tag('og:image:secure_url'), base),
    absoluteHttpUrl(tag('og:image'), base),
    absoluteHttpUrl(tag('twitter:image'), base),
    absoluteHttpUrl(tag('twitter:image:src'), base),
    absoluteHttpUrl(clean(doc, jsonLdImage(ld, node.image)), base),
  );

  // `article:author` is often a profile URL rather than a name; a URL isn't an author name, so skip it.
  const articleAuthor = tag('article:author');
  const author = first(
    jsonLdNames(doc, ld, node.author),
    tag('author'),
    looksLikeUrl(articleAuthor) ? undefined : articleAuthor,
  );

  const publishedAt = first(
    isoDate(tag('article:published_time')),
    isoDate(field('datePublished')),
    isoDate(clean(doc, doc.querySelector('article time[datetime]')?.getAttribute('datetime'))),
  );

  const faviconUrl =
    first(
      largestIcon(doc, ['apple-touch-icon', 'apple-touch-icon-precomposed'], base),
      largestIcon(doc, ['icon'], base),
    ) ?? new URL('/favicon.ico', page).href;

  const lang = clean(doc, doc.documentElement?.getAttribute('lang'));
  const type = first(tag('og:type'), ld.primary ? typesOf(ld.primary)[0] : undefined);

  const metadata: PageMetadata = { title, siteName, canonicalUrl, faviconUrl };
  if (description !== undefined) metadata.description = truncate(description);
  if (imageUrl !== undefined) metadata.imageUrl = imageUrl;
  if (author !== undefined) metadata.author = author;
  if (publishedAt !== undefined) metadata.publishedAt = publishedAt;
  if (lang !== undefined) metadata.lang = lang;
  if (type !== undefined) metadata.type = type;
  return { metadata, warnings };
}
