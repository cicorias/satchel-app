// Page capture pipeline (spec §4.4): clone → images → Defuddle → post-process → Turndown → images → frontmatter
// → guardrails.

import type { ImageRef } from '@satchel/model';
import { itemIdFor, normalizedUrlFor } from '@satchel/model';
import Defuddle from 'defuddle';
import { annotateCodeLanguages } from './code.ts';
import { contentExcerpt } from './excerpt.ts';
import { formatFrontmatter } from './frontmatter.ts';
import { documentBase, postprocessContent, preprocessImages } from './images.ts';
import { htmlToMarkdown } from './markdown/convert.ts';
import { extractMetadata } from './metadata.ts';
import { absoluteHttpUrl, clean, isoDate, truncate } from './text.ts';
import type { CaptureOptions, PageCapture } from './types.ts';

/** Pinned in package.json; a test keeps these in step with the installed versions. */
export const ENGINE = { extractor: 'defuddle@0.19.4', converter: 'turndown@7.2.4' } as const;

export const MAX_MARKDOWN_BYTES = 10 * 1024 * 1024;
const MIN_EXTRACTED_WORDS = 50;
const WORDS_PER_MINUTE = 230;

export class PageTooLargeError extends Error {
  constructor(readonly bytes: number) {
    super(
      `the page converts to ${bytes} bytes of Markdown, over the ${MAX_MARKDOWN_BYTES}-byte limit; save it as a link`,
    );
    this.name = 'PageTooLargeError';
  }
}

const clone = (doc: Document) => doc.cloneNode(true) as Document;

/** Escape what would change a heading's meaning: Markdown punctuation and tag-like "<". */
const escapeHeading = (title: string) => title.replace(/([\\`*_[\]])/g, '\\$1').replace(/<(?=\/?[A-Za-z])/g, '\\<');

const comparable = (text: string) =>
  text
    .replace(/\\(.)/g, '$1')
    .replace(/&/g, ' and ')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();

/**
 * Drop a first heading that repeats the title, since the body already starts with `# title`. "Repeats" means
 * one is a prefix of the other: titles often append the site name, and headings often omit a subtitle.
 */
function dropRepeatedTitle(markdown: string, title: string): string {
  const match = markdown.match(/^#{1,6} (.+)\n*/);
  if (!match?.[1]) return markdown;
  const heading = comparable(match[1]);
  const wanted = comparable(title);
  return heading && (wanted.startsWith(heading) || heading.startsWith(wanted))
    ? markdown.slice(match[0].length)
    : markdown;
}

const IMAGE = /!\[((?:\\.|[^\]\\])*)\]\((<(?:\\.|[^>\\])*>|(?:\\.|[^)\s\\])+)(?:\s+"(?:\\.|[^"\\])*")?\)/g;
const unescapeMarkdown = (s: string) => s.replace(/\\(.)/g, '$1');

/** `ImageRef`s for every image in the Markdown, in order, once per URL. */
export function collectImages(markdown: string): ImageRef[] {
  const seen = new Set<string>();
  const images: ImageRef[] = [];
  for (const match of markdown.matchAll(IMAGE)) {
    const destination = match[2] ?? '';
    const url = unescapeMarkdown(destination.startsWith('<') ? destination.slice(1, -1) : destination);
    if (seen.has(url)) continue;
    seen.add(url);
    const alt = unescapeMarkdown(match[1] ?? '');
    images.push(alt ? { originalUrl: url, alt, status: 'remote' } : { originalUrl: url, status: 'remote' });
  }
  return images;
}

// Han and kana are written without spaces, so each character counts as a word; Hangul uses spaces.
const CJK = /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}]/gu;
const CJK_CHARS_PER_MINUTE = 500;

/** Word count and reading time of the rendered text: Markdown syntax, URLs, and fence markers don't count. */
export function readingStats(markdown: string): { wordCount: number; readingMinutes: number } {
  const text = markdown
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
    .replace(/<[^>]+>/g, ' ')
    .replace(/^```.*$/gm, ' ')
    .replace(/[#>*_~`|[\]-]+/g, ' ');
  const cjk = text.match(CJK)?.length ?? 0;
  const words = text
    .replace(CJK, ' ')
    .split(/\s+/)
    .filter((word) => /[\p{L}\p{N}]/u.test(word)).length;
  return {
    wordCount: words + cjk,
    readingMinutes: Math.ceil(words / WORDS_PER_MINUTE + cjk / CJK_CHARS_PER_MINUTE),
  };
}

export const countWords = (markdown: string) => readingStats(markdown).wordCount;

function fallbackContent(doc: Document, base: string): string {
  const fresh = clone(doc);
  preprocessImages(fresh, base);
  annotateCodeLanguages(fresh);
  const root = fresh.querySelector('main') ?? fresh.querySelector('article') ?? fresh.body;
  for (const el of Array.from(root?.querySelectorAll('script, style, nav, header, footer, aside, form') ?? [])) {
    el.remove();
  }
  return root?.innerHTML ?? '';
}

/**
 * Page mode (§3.1): the article as Markdown with frontmatter. Works on clones, so `doc` is never modified.
 * Throws `PageTooLargeError` past 10 MB, and `UnsupportedUrlError` for a non-http(s) `pageUrl`.
 */
export async function capturePage(doc: Document, opts: CaptureOptions): Promise<PageCapture> {
  const { pageUrl } = opts;
  const now = (opts.now ?? new Date()).toISOString();
  const { metadata, warnings } = extractMetadata(doc, pageUrl, { bodyExcerpt: false });

  const working = clone(doc);
  const base = documentBase(working, pageUrl);
  preprocessImages(working, base);
  annotateCodeLanguages(working);

  let contentHtml: string;
  let defuddled: ReturnType<Defuddle['parse']> | undefined;
  if (opts.selectionHtml !== undefined) {
    contentHtml = opts.selectionHtml;
  } else {
    // useAsync: false keeps extraction on the device: with it on, Defuddle may fetch content from
    // third-party services (ADR-0006, Spike C).
    defuddled = new Defuddle(working, { url: pageUrl, useAsync: false }).parse();
    contentHtml = defuddled.content;
    if (defuddled.wordCount < MIN_EXTRACTED_WORDS) {
      contentHtml = fallbackContent(doc, base);
      warnings.push('low-confidence-extraction');
    }
  }

  const content = postprocessContent(working, contentHtml, base, warnings);
  const converted = dropRepeatedTitle(htmlToMarkdown(content), metadata.title);

  // Defuddle fills the gaps the data-island resolver left (§4.2); the content excerpt comes last (§4.3).
  if (defuddled) {
    const excerptHolder = working.createElement('div');
    excerptHolder.innerHTML = content;
    const description = metadata.description ?? clean(working, defuddled.description) ?? contentExcerpt(excerptHolder);
    if (description !== undefined) metadata.description = truncate(description);
    const author = metadata.author ?? clean(working, defuddled.author);
    if (author !== undefined) metadata.author = author;
    const publishedAt = metadata.publishedAt ?? isoDate(clean(working, defuddled.published));
    if (publishedAt !== undefined) metadata.publishedAt = publishedAt;
    const imageUrl = metadata.imageUrl ?? absoluteHttpUrl(clean(working, defuddled.image), base);
    if (imageUrl !== undefined) metadata.imageUrl = imageUrl;
    const lang = metadata.lang ?? clean(working, defuddled.language);
    if (lang !== undefined) metadata.lang = lang;
  }

  const bodyMarkdown = `# ${escapeHeading(metadata.title)}\n${converted ? `\n${converted}\n` : ''}`;
  const stats = readingStats(converted);
  const frontmatter = formatFrontmatter({
    id: itemIdFor(normalizedUrlFor(pageUrl, metadata.canonicalUrl)),
    type: 'page',
    title: metadata.title,
    url: pageUrl,
    canonical: metadata.canonicalUrl,
    ...(metadata.siteName !== undefined && { site: metadata.siteName }),
    ...(metadata.author !== undefined && { author: metadata.author }),
    ...(metadata.publishedAt !== undefined && { published: metadata.publishedAt }),
    saved: now,
    updated: now,
    ...(metadata.description !== undefined && { description: metadata.description }),
    ...(metadata.imageUrl !== undefined && { image: metadata.imageUrl }),
    tags: [],
    engine: `${ENGINE.extractor} + ${ENGINE.converter}`,
  });
  const markdown = `${frontmatter}\n${bodyMarkdown}`;

  // Cheap upper bound first (≤ 3 UTF-8 bytes per UTF-16 unit), exact count only near the limit.
  if (markdown.length * 3 > MAX_MARKDOWN_BYTES) {
    const bytes = new TextEncoder().encode(markdown).length;
    if (bytes > MAX_MARKDOWN_BYTES) throw new PageTooLargeError(bytes);
  }

  return {
    metadata,
    warnings,
    markdown,
    bodyMarkdown,
    images: collectImages(bodyMarkdown),
    stats,
    engine: { ...ENGINE },
  };
}
