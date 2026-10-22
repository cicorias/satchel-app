// String and URL normalization shared by the resolvers (spec §4.2, "Normalization").

const ENTITY = /&(?:#\d+|#x[0-9a-f]+|[a-z][a-z0-9]+);/i;

/**
 * Decode HTML entities that survived into a string (common in JSON-LD and in double-encoded meta tags).
 * The HTML parser does the decoding, in a detached element. Every `<` is escaped first, so the input can't
 * form markup: nothing loads or runs, and the page isn't touched. Only `&name;` forms with a semicolon are
 * decoded, so query strings such as `?a=1&copy=2` stay intact.
 */
export function decodeEntities(doc: Document, value: string): string {
  if (!ENTITY.test(value)) return value;
  const scratch = doc.createElement('div');
  scratch.innerHTML = value.replace(/</g, '&lt;');
  return scratch.textContent ?? value;
}

/** Decode entities, collapse whitespace, and trim. Non-strings and blank strings become `undefined`. */
export function clean(doc: Document, value: unknown): string | undefined {
  if (typeof value !== 'string') return undefined;
  const text = decodeEntities(doc, value).replace(/\s+/g, ' ').trim();
  return text === '' ? undefined : text;
}

/**
 * Truncate to `max` characters including the ellipsis, at the last sentence end if one falls in the
 * second half, otherwise at the last word boundary.
 */
export function truncate(text: string, max = 300): string {
  if (text.length <= max) return text;
  const room = text.slice(0, max - 1);
  const sentenceEnd = Math.max(room.lastIndexOf('. '), room.lastIndexOf('! '), room.lastIndexOf('? '));
  if (sentenceEnd >= max / 2) return `${room.slice(0, sentenceEnd + 1)}…`;
  const space = room.lastIndexOf(' ');
  const cut = space > 0 ? room.slice(0, space) : room;
  return `${cut.replace(/[\s,;:–—-]+$/, '')}…`;
}

/** Resolve against `base` and keep only http(s) results. */
export function absoluteHttpUrl(value: string | undefined, base: string): string | undefined {
  if (value === undefined) return undefined;
  try {
    const url = new URL(value, base);
    return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : undefined;
  } catch {
    return undefined;
  }
}

/** Parse any date the page offers into ISO 8601 (UTC). Unparseable dates are dropped. */
export function isoDate(value: string | undefined): string | undefined {
  if (value === undefined) return undefined;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? undefined : new Date(ms).toISOString();
}
