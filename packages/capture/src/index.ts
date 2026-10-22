// @satchel/capture (spec §4): DOM in, data out. Must never touch window, location, chrome.*, or browser.*,
// so every input arrives as an argument.

import app from '../../../config/app.config.json' with { type: 'json' };
import { extractMetadata } from './metadata.ts';
import type { CaptureOptions, LinkCapture } from './types.ts';

export { type Frontmatter, formatFrontmatter } from './frontmatter.ts';
export { htmlToMarkdown } from './markdown/convert.ts';
export { extractMetadata, type MetadataOptions, type MetadataResult, type PageMetadata } from './metadata.ts';
export {
  capturePage,
  collectImages,
  countWords,
  ENGINE,
  MAX_MARKDOWN_BYTES,
  PageTooLargeError,
  readingStats,
} from './page.ts';
export type { CaptureOptions, LinkCapture, PageCapture } from './types.ts';

/** The app version (CalVer, ADR-0015) from config/app.config.json. */
export const version: string = app.version;

/** Link mode (§3.1): metadata only, from <head> and JSON-LD, plus the body excerpt fallback. Never modifies `doc`. */
export function captureLink(doc: Document, opts: CaptureOptions): LinkCapture {
  return extractMetadata(doc, opts.pageUrl);
}
