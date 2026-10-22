// @satchel/capture (spec §4): DOM in, data out. Must never touch window, location, chrome.*, or browser.*,
// so every input arrives as an argument.

import { extractMetadata, type PageMetadata } from './metadata.ts';

export { extractMetadata, type MetadataResult, type PageMetadata } from './metadata.ts';

export const version = '0.0.0';

export interface CaptureOptions {
  /** The document's URL. Required, because a cloned DOM may not know it. */
  pageUrl: string;
  /** Set when saving a selection only (FR-10). */
  selectionHtml?: string;
  /** Injectable clock for deterministic tests. */
  now?: Date;
}

export interface LinkCapture {
  metadata: PageMetadata;
  warnings: string[];
}

/** Link mode (§3.1): metadata only, from <head> and JSON-LD. Never modifies `doc`. */
export function captureLink(doc: Document, opts: CaptureOptions): LinkCapture {
  return extractMetadata(doc, opts.pageUrl);
}
