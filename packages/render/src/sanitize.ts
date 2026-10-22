// Sanitizing markdown-it's output (spec §11): DOMPurify with an explicit allowlist, then a pass of our own over the
// sanitized (inert) DOM for the URL policy, link attributes, task-list checkboxes, and the remote-image toggle.

import createDOMPurify, { type Config, type DOMPurify, type WindowLike } from 'dompurify';

/** Elements Satchel Markdown can produce, plus the inline HTML that Turndown keeps. No SVG or MathML at all. */
const ALLOWED_TAGS = [
  'a',
  'abbr',
  'b',
  'blockquote',
  'br',
  'caption',
  'cite',
  'code',
  'col',
  'colgroup',
  'dd',
  'del',
  'details',
  'dfn',
  'div',
  'dl',
  'dt',
  'em',
  'figcaption',
  'figure',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'i',
  'img',
  'input', // task-list checkboxes only; anything else is removed in postprocess
  'ins',
  'kbd',
  'li',
  'mark',
  'ol',
  'p',
  'pre',
  'q',
  's',
  'samp',
  'section',
  'small',
  'span',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'u',
  'ul',
  'var',
  'wbr',
];

const ALLOWED_ATTR = [
  'align',
  'alt',
  'checked',
  'class',
  'colspan',
  'data-callout',
  'datetime',
  'disabled',
  'height',
  'href',
  'id',
  'open',
  'reversed',
  'rowspan',
  'scope',
  'span',
  'src',
  'start',
  'title',
  'type',
  'width',
];

/** URL-valued attributes must be http(s), mailto, tel, or scheme-less; postprocess narrows this further. */
const ALLOWED_URI_REGEXP = /^(?:(?:https?|mailto|tel):|[^a-z]|[a-z+.-]+(?:[^a-z+.\-:]|$))/i;

const CONFIG: Config = {
  ALLOWED_TAGS,
  ALLOWED_ATTR,
  ALLOW_DATA_ATTR: false,
  ALLOW_ARIA_ATTR: false,
  ALLOW_UNKNOWN_PROTOCOLS: false,
  ALLOWED_URI_REGEXP,
  ALLOW_SELF_CLOSE_IN_ATTR: false,
  SAFE_FOR_TEMPLATES: false,
  WHOLE_DOCUMENT: false,
  // Parse as body content even when the input starts with something like <frameset> that would replace <body>.
  FORCE_BODY: true,
  KEEP_CONTENT: true,
  // Prefix ids with `user-content-` so saved content can't clobber the host page's globals or ids (as GitHub does).
  SANITIZE_DOM: true,
  SANITIZE_NAMED_PROPS: true,
};

const ID_PREFIX = 'user-content-';

export interface SanitizeOptions {
  remoteImages: boolean;
  linkTarget: string | null;
  resolveImage: ((src: string) => string | null | undefined) | undefined;
}

export interface SanitizeResult {
  html: string;
  blockedImages: number;
}

export interface Sanitizer {
  sanitize(html: string, opts: SanitizeOptions): SanitizeResult;
}

export function createSanitizer(window: WindowLike): Sanitizer {
  const purify: DOMPurify = createDOMPurify(window);
  if (!purify.isSupported) throw new Error('SatchelRender: DOMPurify is not supported by the provided window');
  return {
    sanitize(html, opts) {
      const body = purify.sanitize(html, { ...CONFIG, RETURN_DOM: true }) as HTMLElement | null;
      if (!body) return { html: '', blockedImages: 0 };
      const blockedImages = postprocess(body, opts);
      return { html: body.innerHTML, blockedImages };
    },
  };
}

// The sanitized body belongs to a DOMParser document with no browsing context, so nothing in it loads or runs.
function postprocess(root: HTMLElement, opts: SanitizeOptions): number {
  const doc = root.ownerDocument;
  let blocked = 0;

  for (const a of Array.from(root.querySelectorAll('a'))) {
    const href = a.getAttribute('href');
    if (href === null) continue;
    const kind = classifyLink(href);
    if (kind === 'unsafe') {
      a.removeAttribute('href');
      continue;
    }
    if (kind === 'fragment') {
      // Follow the id prefixing that SANITIZE_NAMED_PROPS applied, so footnote links still land.
      const target = href.trim().slice(1);
      if (target && !target.startsWith(ID_PREFIX)) a.setAttribute('href', `#${ID_PREFIX}${target}`);
      continue;
    }
    a.setAttribute('rel', 'noopener noreferrer');
    if (opts.linkTarget) a.setAttribute('target', opts.linkTarget);
  }

  for (const img of Array.from(root.querySelectorAll('img'))) {
    const src = img.getAttribute('src')?.trim() ?? '';
    let finalSrc: string | null = null;
    let remote = false;
    if (isRemote(src)) {
      remote = true;
      // A protocol-relative URL would resolve against the host page (chrome-extension:, an app scheme), so pin https.
      if (opts.remoteImages) finalSrc = src.startsWith('//') ? `https:${src}` : src;
    } else if (isImageDataUri(src)) {
      finalSrc = src;
    } else if (src && opts.resolveImage && isRelative(src)) {
      const resolved = opts.resolveImage(src);
      if (resolved && isSafeResolvedImage(resolved)) finalSrc = resolved;
    }
    if (finalSrc !== null) {
      img.setAttribute('src', finalSrc);
      if (remote) img.setAttribute('referrerpolicy', 'no-referrer');
      img.setAttribute('loading', 'lazy');
      img.setAttribute('decoding', 'async');
      continue;
    }
    // Not loaded: keep the alt text (and the URL as a tooltip) so the reader knows an image was here.
    const placeholder = doc.createElement('span');
    placeholder.className = remote ? 'image-blocked' : 'image-missing';
    const alt = img.getAttribute('alt')?.trim();
    placeholder.textContent = alt || 'Image';
    if (src && classifyLink(src) !== 'unsafe') placeholder.setAttribute('title', src);
    img.replaceWith(placeholder);
    if (remote) blocked++;
  }

  // Only disabled task-list checkboxes survive; every other <input> (text fields, image buttons) is dropped.
  for (const input of Array.from(root.querySelectorAll('input'))) {
    if (input.getAttribute('type')?.toLowerCase() !== 'checkbox') {
      input.remove();
      continue;
    }
    const checked = input.hasAttribute('checked');
    const cls = input.getAttribute('class');
    for (const name of input.getAttributeNames()) input.removeAttribute(name);
    if (cls) input.setAttribute('class', cls);
    input.setAttribute('type', 'checkbox');
    input.setAttribute('disabled', '');
    if (checked) input.setAttribute('checked', '');
  }

  return blocked;
}

type LinkKind = 'fragment' | 'external' | 'unsafe';

// Browsers ignore ASCII tab/newline and leading control characters/spaces when parsing a URL scheme.
// biome-ignore lint/suspicious/noControlCharactersInRegex: stripping control characters is the point
const IGNORED = /[\u0000- \u007f-\u009f]/g;

function scheme(url: string): string | null {
  const m = /^([a-z][a-z0-9+.-]*):/i.exec(url.replace(IGNORED, ''));
  return m?.[1]?.toLowerCase() ?? null;
}

function classifyLink(href: string): LinkKind {
  const s = scheme(href);
  if (s === null) return href.trim().startsWith('#') ? 'fragment' : 'unsafe';
  return s === 'http' || s === 'https' || s === 'mailto' || s === 'tel' ? 'external' : 'unsafe';
}

function isRemote(src: string): boolean {
  const s = scheme(src);
  return s === 'http' || s === 'https' || src.startsWith('//');
}

const IMAGE_DATA = /^data:image\/(?:png|jpe?g|gif|webp|avif|bmp|svg\+xml)(?:;[a-z0-9=._+-]+)*;base64,[a-z0-9+/=\s]*$/i;

function isImageDataUri(src: string): boolean {
  return IMAGE_DATA.test(src);
}

/** Provider-neutral asset paths such as `images/<hash>.png` (spec §10.4). */
function isRelative(src: string): boolean {
  return scheme(src) === null && !src.startsWith('//') && !src.startsWith('#');
}

/** Whatever the host's resolver returns (blob:, an extension or app URL, a data URI) is trusted, except script URLs. */
function isSafeResolvedImage(src: string): boolean {
  const s = scheme(src);
  if (s === 'javascript' || s === 'vbscript') return false;
  if (s === 'data') return isImageDataUri(src);
  return true;
}
