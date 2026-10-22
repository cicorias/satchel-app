// Image and link fix-ups around extraction (spec §4.4 steps 2 and 4). Both run on the cloned document or on
// elements it owns. A cloned document has no browsing context, so nothing here loads or runs.

import { isDangerousUrl } from './markdown/convert.ts';

const LAZY_SRC = ['data-src', 'data-lazy-src', 'data-original'];
const DATA_IMAGE_LIMIT = 8 * 1024;

/** Absolute http(s) URL, or the `data:` URL unchanged. Anything else is `undefined`. */
export function absolutize(value: string | null | undefined, base: string): string | undefined {
  const trimmed = value?.trim();
  if (!trimmed) return undefined;
  if (/^data:/i.test(trimmed)) return trimmed;
  try {
    const url = new URL(trimmed, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : undefined;
  } catch {
    return undefined;
  }
}

/** The base for relative URLs: `<base href>` resolved against the page URL. */
export function documentBase(doc: Document, pageUrl: string): string {
  const href = doc.querySelector('base[href]')?.getAttribute('href');
  return absolutize(href, pageUrl) ?? pageUrl;
}

interface Candidate {
  url: string;
  score: number;
}

/**
 * srcset candidates. Tokens are split on whitespace, not commas, because CDN URLs can contain commas; a
 * descriptor (or a trailing comma) ends a candidate. Width descriptors outrank density descriptors.
 */
function candidates(srcset: string | null): Candidate[] {
  if (!srcset) return [];
  const out: Candidate[] = [];
  let parts: string[] = [];
  const flush = (score: number) => {
    const url = parts.join(' ').replace(/^,\s*/, '').replace(/,$/, '');
    if (url) out.push({ url, score });
    parts = [];
  };
  for (const token of srcset.trim().split(/\s+/)) {
    const width = token.match(/^(\d+)w,?$/);
    const density = token.match(/^(\d+(?:\.\d+)?)x,?$/);
    if (width) flush(Number(width[1]));
    else if (density) flush(Number(density[1]) / 1000);
    else {
      parts.push(token);
      if (token.endsWith(',')) flush(0);
    }
  }
  flush(0);
  return out;
}

function largest(list: Candidate[]): string | undefined {
  let best: Candidate | undefined;
  for (const candidate of list) if (!best || candidate.score > best.score) best = candidate;
  return best?.url;
}

/** Parse the images out of a <noscript> (browsers with scripting on keep its content as text). */
function noscriptImages(doc: Document, noscript: Element): Element[] {
  const holder = doc.createElement('div');
  holder.innerHTML = noscript.children.length > 0 ? noscript.innerHTML : (noscript.textContent ?? '');
  return Array.from(holder.querySelectorAll('img'));
}

const isPlaceholder = (src: string | null) =>
  !src ||
  /^data:image\/(?:gif|svg\+xml)/i.test(src) ||
  /(?:placeholder|blank|spacer|lazy|pixel)\.(?:gif|png|svg)/i.test(src);

/** §4.4 step 2: lazy-load attributes, the largest srcset/<picture> candidate, <noscript> fallbacks, absolute src. */
export function preprocessImages(doc: Document, base: string): void {
  for (const noscript of Array.from(doc.querySelectorAll('noscript'))) {
    const images = noscriptImages(doc, noscript);
    if (images.length === 0) continue;
    const previous = noscript.previousElementSibling;
    const placeholder = previous?.nodeName === 'IMG' ? previous : previous?.querySelector('img');
    const [first] = images;
    if (placeholder && first && images.length === 1 && isPlaceholder(placeholder.getAttribute('src'))) {
      for (const attr of ['src', 'srcset', 'alt']) {
        const value = first.getAttribute(attr);
        if (value && (attr !== 'alt' || !placeholder.getAttribute('alt'))) placeholder.setAttribute(attr, value);
      }
      for (const attr of LAZY_SRC) placeholder.removeAttribute(attr);
    } else {
      for (const img of images) noscript.parentNode?.insertBefore(img, noscript);
    }
    noscript.remove();
  }

  for (const el of Array.from(doc.querySelectorAll('img, source'))) {
    for (const attr of LAZY_SRC) {
      const value = el.getAttribute(attr);
      if (value) el.setAttribute('src', value);
    }
    const lazySrcset = el.getAttribute('data-srcset');
    if (lazySrcset) el.setAttribute('srcset', lazySrcset);
  }

  for (const img of Array.from(doc.querySelectorAll('img'))) {
    const list = candidates(img.getAttribute('srcset'));
    const picture = img.parentNode?.nodeName === 'PICTURE' ? (img.parentNode as Element) : undefined;
    if (picture) {
      for (const source of Array.from(picture.querySelectorAll('source'))) {
        list.push(...candidates(source.getAttribute('srcset') ?? source.getAttribute('src')));
        source.remove();
      }
    }
    const best = largest(list);
    if (best) img.setAttribute('src', best);
    img.removeAttribute('srcset');
    img.removeAttribute('sizes');
    const src = absolutize(img.getAttribute('src'), base);
    if (src) img.setAttribute('src', src);
    else img.removeAttribute('src');
  }
}

/** §4.4 step 4, on extracted content HTML: absolute links, no tracking pixels, small `data:` images only. */
export function postprocessContent(doc: Document, html: string, base: string, warnings: string[]): string {
  const container = doc.createElement('div');
  container.innerHTML = html;

  for (const a of Array.from(container.querySelectorAll('a[href]'))) {
    const href = a.getAttribute('href')?.trim() ?? '';
    if (/^(?:mailto|tel):/i.test(href)) continue;
    const absolute = isDangerousUrl(href) ? undefined : absolutize(href, base);
    if (absolute && !absolute.startsWith('data:')) a.setAttribute('href', absolute);
    else a.removeAttribute('href');
  }

  let droppedDataImages = 0;
  for (const img of Array.from(container.querySelectorAll('img'))) {
    const src = absolutize(img.getAttribute('src'), base);
    const width = Number(img.getAttribute('width'));
    const height = Number(img.getAttribute('height'));
    const isPixel = (img.hasAttribute('width') && width <= 2) || (img.hasAttribute('height') && height <= 2);
    if (!src || isPixel || isDangerousUrl(src)) {
      img.remove();
    } else if (src.startsWith('data:') && src.length > (DATA_IMAGE_LIMIT * 4) / 3 + 64) {
      img.remove();
      droppedDataImages++;
    } else {
      img.setAttribute('src', src);
    }
  }
  if (droppedDataImages > 0) warnings.push('dropped-large-data-image');

  return container.innerHTML;
}
