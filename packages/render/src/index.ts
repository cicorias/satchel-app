// @satchel/render (spec §9.1.4, §11): Satchel Markdown in, sanitized HTML out. Shared by the extension's Library page
// and the Apple host app's WKWebView (via the IIFE), so saved pages render the same everywhere.
//
// DOMPurify needs a DOM. In a browser or WKWebView the global `window` is used; tests and other hosts pass one in.

import type { WindowLike } from 'dompurify';
import { splitFrontmatter } from './frontmatter.ts';
import { createMarkdown } from './markdown.ts';
import { createSanitizer } from './sanitize.ts';

export type { WindowLike } from 'dompurify';
export { type FrontmatterSplit, splitFrontmatter } from './frontmatter.ts';

export const version = '0.0.0';

export interface RendererInit {
  /** The DOM DOMPurify works in. Defaults to `globalThis.window`. */
  window?: WindowLike;
  /** Pass inline HTML in the Markdown to the sanitizer instead of escaping it. Defaults to true (Turndown keeps some). */
  html?: boolean;
}

export interface RenderOptions {
  /**
   * Load `http(s)` images (spec §11, "Load remote images"). Defaults to false: remote images become an
   * `<span class="image-blocked">` placeholder holding the alt text, so no third-party server is contacted.
   */
  remoteImages?: boolean;
  /** `target` for links that leave the document. Defaults to `_blank`; `null` omits it. In-page `#` links never get one. */
  linkTarget?: string | null;
  /**
   * Maps a relative image path (`images/<hash>.<ext>`, spec §10.4) to a loadable URL, e.g. a `blob:` URL from the
   * active provider. Without it, or when it returns null, the image becomes an `<span class="image-missing">`.
   */
  resolveImage?: (src: string) => string | null | undefined;
  /** Distinguishes footnote ids when several documents are rendered into one page. */
  docId?: string;
}

export interface RenderResult {
  /** Sanitized HTML for the Markdown body. Frontmatter is never part of it. */
  html: string;
  /** The raw YAML between the frontmatter fences, or null when there is none. Not parsed. */
  frontmatter: string | null;
  /** How many remote images were replaced by placeholders (offer "Load images" when this is above zero). */
  blockedImages: number;
}

export interface Renderer {
  render(markdown: string, options?: RenderOptions): RenderResult;
}

export function createRenderer(init: RendererInit = {}): Renderer {
  const win = init.window ?? (globalThis as { window?: WindowLike }).window;
  if (!win) throw new Error('SatchelRender: no DOM available; pass createRenderer({ window })');
  const md = createMarkdown({ html: init.html ?? true });
  const sanitizer = createSanitizer(win);
  return {
    render(markdown, options = {}) {
      const { frontmatter, body } = splitFrontmatter(markdown);
      const env: Record<string, unknown> = {};
      if (options.docId) env.docId = options.docId;
      const dirty = md.render(body, env);
      const { html, blockedImages } = sanitizer.sanitize(dirty, {
        remoteImages: options.remoteImages ?? false,
        linkTarget: options.linkTarget === undefined ? '_blank' : options.linkTarget,
        resolveImage: options.resolveImage,
      });
      return { html, frontmatter, blockedImages };
    },
  };
}

let shared: Renderer | undefined;

/** Renders with a renderer bound to the global `window`, created on first use. */
export function render(markdown: string, options?: RenderOptions): RenderResult {
  shared ??= createRenderer();
  return shared.render(markdown, options);
}
