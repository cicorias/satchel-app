// Body excerpt fallback for the description (spec §4.3).

const MIN_LENGTH = 80;
const EXCLUDED_ANCESTORS = new Set(['NAV', 'HEADER', 'FOOTER', 'ASIDE']);
const EXCLUDED_NAMES = /cookie|consent|subscribe|newsletter|promo|banner/i;

/** The paragraph's text without <sup> citation markers ("[1]") or footnote numbers. */
function text(p: Element): string {
  const copy = p.cloneNode(true) as Element;
  for (const sup of Array.from(copy.querySelectorAll('sup'))) sup.remove();
  return (copy.textContent ?? '').replace(/\s+/g, ' ').trim();
}

function isExcluded(p: Element, root: Element): boolean {
  for (let el: Element | null = p; el && el !== root.parentElement; el = el.parentElement) {
    if (el !== p && EXCLUDED_ANCESTORS.has(el.nodeName)) return true;
    const names = `${el.getAttribute('class') ?? ''} ${el.getAttribute('id') ?? ''}`;
    if (EXCLUDED_NAMES.test(names)) return true;
  }
  return false;
}

/**
 * Link mode: the first <p> of at least 80 characters in <article>, then <main>, then <body>, skipping
 * navigation chrome and cookie, consent, newsletter, and promo containers.
 */
export function linkExcerpt(doc: Document): string | undefined {
  for (const selector of ['article', 'main', 'body']) {
    const root = doc.querySelector(selector);
    if (!root) continue;
    for (const p of Array.from(root.querySelectorAll('p'))) {
      const value = text(p);
      if (value.length >= MIN_LENGTH && !isExcluded(p, root)) return value;
    }
  }
  return undefined;
}

/** Page mode: the first paragraph of the extracted content with at least 80 characters. */
export function contentExcerpt(container: Element): string | undefined {
  for (const p of Array.from(container.querySelectorAll('p'))) {
    const value = text(p);
    if (value.length >= MIN_LENGTH) return value;
  }
  return undefined;
}
