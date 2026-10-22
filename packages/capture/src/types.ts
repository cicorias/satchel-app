// Public types of the capture API (spec §4.1).

import type { ImageRef } from '@satchel/model';
import type { PageMetadata } from './metadata.ts';

export interface CaptureOptions {
  /** The document's URL. Required, because a cloned DOM may not know it. */
  pageUrl: string;
  /** Set when saving a selection only (FR-10): this HTML is converted instead of the extracted article. */
  selectionHtml?: string;
  /** Injectable clock for deterministic tests. */
  now?: Date;
}

export interface LinkCapture {
  metadata: PageMetadata;
  warnings: string[];
}

export interface PageCapture extends LinkCapture {
  /** The full document: frontmatter, then the body. */
  markdown: string;
  /** The body without frontmatter, starting with `# title`. */
  bodyMarkdown: string;
  /** Every image referenced in `bodyMarkdown`, in document order. */
  images: ImageRef[];
  stats: { wordCount: number; readingMinutes: number };
  /** For example `defuddle@0.19.4` and `turndown@7.2.4`. */
  engine: { extractor: string; converter: string };
}
