import { parseHTML } from 'linkedom';
import { describe, expect, test } from 'vitest';
import { captureLink, extractMetadata } from '../src/index.ts';
import { truncate } from '../src/text.ts';

const PAGE = 'https://www.example.com/blog/post-1';

function doc(head: string, body = '', htmlAttrs = ''): Document {
  return parseHTML(`<!doctype html><html ${htmlAttrs}><head>${head}</head><body>${body}</body></html>`)
    .document as unknown as Document;
}

const meta = (head: string, body = '', htmlAttrs = '') => extractMetadata(doc(head, body, htmlAttrs), PAGE).metadata;
const ld = (value: unknown) => `<script type="application/ld+json">${JSON.stringify(value)}</script>`;
const article = (fields: Record<string, unknown>) =>
  ld({ '@context': 'https://schema.org', '@type': 'Article', ...fields });

describe('title', () => {
  const all = `<meta property="og:title" content="OG"><meta name="twitter:title" content="Twitter">
    ${article({ headline: 'Headline', name: 'Name' })}<title>Tag</title>`;
  test.each([
    ['og:title', all, 'OG'],
    ['twitter:title', all.replace(/<meta property="og:title"[^>]*>/, ''), 'Twitter'],
    ['JSON-LD headline', `${article({ headline: 'Headline', name: 'Name' })}<title>Tag</title>`, 'Headline'],
    ['JSON-LD name', `${article({ name: 'Name' })}<title>Tag</title>`, 'Name'],
    ['<title>', '<title>Tag</title>', 'Tag'],
    ['hostname + path', '', 'www.example.com/blog/post-1'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).title).toBe(expected);
  });

  test('skips blank values', () => {
    expect(meta('<meta property="og:title" content="   "><title>Tag</title>').title).toBe('Tag');
  });

  test('a bare host has no trailing slash', () => {
    expect(extractMetadata(doc(''), 'https://example.com/').metadata.title).toBe('example.com');
  });
});

describe('description', () => {
  test.each([
    ['og:description', '<meta property="og:description" content="OG"><meta name="description" content="Meta">', 'OG'],
    [
      'twitter:description',
      '<meta name="twitter:description" content="Tw"><meta name="description" content="Meta">',
      'Tw',
    ],
    ['<meta name="description">', `<meta name="description" content="Meta">${article({ description: 'LD' })}`, 'Meta'],
    ['JSON-LD description', article({ description: 'LD' }), 'LD'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).description).toBe(expected);
  });

  test('is absent when no source has one (the body excerpt comes in §4.3)', () => {
    expect('description' in meta('<title>x</title>')).toBe(false);
  });

  test('is truncated to 300 characters', () => {
    const long = `${'word '.repeat(100)}end`;
    const description = meta(`<meta name="description" content="${long}">`).description ?? '';
    expect(description.length).toBeLessThanOrEqual(300);
    expect(description.endsWith('…')).toBe(true);
  });
});

describe('truncate', () => {
  test('leaves short text alone', () => {
    expect(truncate('Short.')).toBe('Short.');
    expect(truncate('x'.repeat(300))).toBe('x'.repeat(300));
  });

  test('cuts at the last sentence end in the second half', () => {
    const text = `${'a'.repeat(200)}. ${'b '.repeat(100)}`;
    expect(truncate(text)).toBe(`${'a'.repeat(200)}.…`);
  });

  test('otherwise cuts at a word boundary and trims trailing punctuation', () => {
    const text = `${'Lorem ipsum, '.repeat(30)}`;
    const out = truncate(text);
    expect(out.length).toBeLessThanOrEqual(300);
    expect(out).toMatch(/ipsum…$/);
  });

  test('hard-cuts a single long word', () => {
    expect(truncate('x'.repeat(400))).toBe(`${'x'.repeat(299)}…`);
  });
});

describe('siteName', () => {
  test.each([
    [
      'og:site_name',
      `<meta property="og:site_name" content="OG Site">${article({ publisher: { name: 'Pub' } })}`,
      'OG Site',
    ],
    [
      'JSON-LD publisher.name',
      `${article({ publisher: { name: 'Pub' } })}<meta name="application-name" content="App">`,
      'Pub',
    ],
    ['application-name', '<meta name="application-name" content="App">', 'App'],
    ['hostname without www.', '', 'example.com'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).siteName).toBe(expected);
  });

  test('follows a publisher @id reference into @graph', () => {
    const graph = ld({
      '@context': 'https://schema.org',
      '@graph': [
        { '@type': 'Article', headline: 'H', publisher: { '@id': 'https://example.com/#org' } },
        { '@type': 'Organization', '@id': 'https://example.com/#org', name: 'Example Org' },
      ],
    });
    expect(meta(graph).siteName).toBe('Example Org');
  });
});

describe('canonicalUrl', () => {
  test.each([
    [
      '<link rel=canonical>',
      '<link rel="canonical" href="https://example.com/c"><meta property="og:url" content="https://example.com/og">',
      'https://example.com/c',
    ],
    ['og:url', '<meta property="og:url" content="https://example.com/og">', 'https://example.com/og'],
    ['pageUrl', '', PAGE],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).canonicalUrl).toBe(expected);
  });

  test('resolves a relative canonical against <base href>', () => {
    expect(meta('<base href="https://cdn.example.com/root/"><link rel="canonical" href="post">').canonicalUrl).toBe(
      'https://cdn.example.com/root/post',
    );
  });

  test('skips non-http(s) values', () => {
    expect(
      meta('<link rel="canonical" href="javascript:void(0)"><meta property="og:url" content="ftp://x/y">').canonicalUrl,
    ).toBe(PAGE);
  });
});

describe('imageUrl', () => {
  test.each([
    [
      'og:image:secure_url',
      '<meta property="og:image:secure_url" content="https://e.com/s.png"><meta property="og:image" content="http://e.com/o.png">',
      'https://e.com/s.png',
    ],
    [
      'og:image',
      '<meta property="og:image" content="/o.png"><meta name="twitter:image" content="/t.png">',
      'https://www.example.com/o.png',
    ],
    ['twitter:image', '<meta name="twitter:image" content="https://e.com/t.png">', 'https://e.com/t.png'],
    ['twitter:image:src', '<meta name="twitter:image:src" content="https://e.com/ts.png">', 'https://e.com/ts.png'],
    ['a JSON-LD image string', article({ image: 'https://e.com/ld.png' }), 'https://e.com/ld.png'],
    [
      'a JSON-LD image object',
      article({ image: { '@type': 'ImageObject', url: 'https://e.com/obj.png' } }),
      'https://e.com/obj.png',
    ],
    [
      'the first JSON-LD image in an array',
      article({ image: ['https://e.com/1.png', 'https://e.com/2.png'] }),
      'https://e.com/1.png',
    ],
    ['an array of image objects', article({ image: [{ url: 'https://e.com/a.png' }] }), 'https://e.com/a.png'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).imageUrl).toBe(expected);
  });

  test('is absent when there is none', () => {
    expect('imageUrl' in meta('')).toBe(false);
  });
});

describe('author', () => {
  test.each([
    ['JSON-LD author.name', `${article({ author: { name: 'Ada' } })}<meta name="author" content="Meta">`, 'Ada'],
    [
      'several JSON-LD authors, joined',
      article({ author: [{ name: 'Ada' }, { name: 'Grace' }, 'Linus'] }),
      'Ada, Grace, Linus',
    ],
    [
      '<meta name="author">',
      '<meta name="author" content="Meta Author"><meta property="article:author" content="AA">',
      'Meta Author',
    ],
    ['article:author', '<meta property="article:author" content="Article Author">', 'Article Author'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).author).toBe(expected);
  });

  test('skips an article:author that is a profile URL', () => {
    expect('author' in meta('<meta property="article:author" content="https://facebook.com/someone">')).toBe(false);
  });

  test('follows an author @id reference', () => {
    const graph = ld({
      '@graph': [
        { '@type': 'BlogPosting', headline: 'H', author: { '@id': '#ada' } },
        { '@type': 'Person', '@id': '#ada', name: 'Ada Lovelace' },
      ],
    });
    expect(meta(graph).author).toBe('Ada Lovelace');
  });
});

describe('publishedAt', () => {
  test.each([
    [
      'article:published_time',
      `<meta property="article:published_time" content="2026-10-01T08:00:00+02:00">${article({ datePublished: '2020-01-01' })}`,
      '2026-10-01T06:00:00.000Z',
    ],
    ['JSON-LD datePublished', article({ datePublished: '2026-09-30' }), '2026-09-30T00:00:00.000Z'],
  ])('falls back to %s', (_, head, expected) => {
    expect(meta(head).publishedAt).toBe(expected);
  });

  test('falls back to the first <time datetime> inside <article>', () => {
    const body =
      '<time datetime="2019-01-01">outside</time><article><time datetime="2026-08-15T12:00:00Z">x</time><time datetime="2026-08-16">y</time></article>';
    expect(meta('', body).publishedAt).toBe('2026-08-15T12:00:00.000Z');
  });

  test('drops dates it cannot parse', () => {
    expect('publishedAt' in meta('<meta property="article:published_time" content="last Tuesday">')).toBe(false);
  });
});

describe('faviconUrl', () => {
  test('prefers the largest apple-touch-icon', () => {
    const head = `<link rel="icon" href="/fav.svg" sizes="any"><link rel="apple-touch-icon" href="/t120.png" sizes="120x120">
      <link rel="apple-touch-icon" href="/t180.png" sizes="180x180"><link rel="apple-touch-icon-precomposed" href="/t152.png" sizes="152x152">`;
    expect(meta(head).faviconUrl).toBe('https://www.example.com/t180.png');
  });

  test('then the largest rel=icon, with sizes=any beating fixed sizes', () => {
    const head =
      '<link rel="shortcut icon" href="/16.png" sizes="16x16"><link rel="icon" href="/32.png" sizes="16x16 32x32"><link rel="icon" href="/f.svg" sizes="any">';
    expect(meta(head).faviconUrl).toBe('https://www.example.com/f.svg');
    expect(
      meta(
        '<link rel="shortcut icon" href="/16.png" sizes="16x16"><link rel="icon" href="/32.png" sizes="16x16 32x32">',
      ).faviconUrl,
    ).toBe('https://www.example.com/32.png');
  });

  test('skips data: icons and falls back to /favicon.ico on the page origin', () => {
    expect(meta('<link rel="icon" href="data:image/png;base64,AAAA">').faviconUrl).toBe(
      'https://www.example.com/favicon.ico',
    );
  });

  test('resolves against <base href>', () => {
    expect(meta('<base href="https://static.example.com/"><link rel="icon" href="i.png">').faviconUrl).toBe(
      'https://static.example.com/i.png',
    );
  });
});

describe('lang and type', () => {
  test('lang comes from <html lang>', () => {
    expect(meta('', '', 'lang="en-GB"').lang).toBe('en-GB');
    expect('lang' in meta('')).toBe(false);
  });

  test.each([
    ['og:type', `<meta property="og:type" content="article">${article({})}`, 'article'],
    ['JSON-LD @type', ld({ '@type': 'schema:Recipe', name: 'Soup' }), 'Recipe'],
  ])('type falls back to %s', (_, head, expected) => {
    expect(meta(head).type).toBe(expected);
  });
});

describe('JSON-LD rules', () => {
  test('invalid JSON is skipped with a warning', () => {
    const result = extractMetadata(
      doc(`<script type="application/ld+json">{ not json</script>${article({ headline: 'Valid' })}`),
      PAGE,
    );
    expect(result.warnings).toEqual(['invalid-json-ld']);
    expect(result.metadata.title).toBe('Valid');
  });

  test('top-level arrays and @graph are flattened', () => {
    const head = ld([
      { '@type': 'BreadcrumbList', name: 'Crumbs' },
      { '@graph': [{ '@type': 'NewsArticle', headline: 'Deep' }] },
    ]);
    expect(meta(head).title).toBe('Deep');
  });

  test('preferred types win over earlier nodes, in the listed order', () => {
    const head = ld({
      '@graph': [
        { '@type': 'WebSite', name: 'Site' },
        { '@type': 'WebPage', name: 'Page' },
        { '@type': ['Thing', 'BlogPosting'], headline: 'Post' },
      ],
    });
    expect(meta(head).title).toBe('Post');
  });

  test('without a preferred type, the first node with a name or headline is used', () => {
    expect(meta(ld([{ '@type': 'Thing' }, { '@type': 'Event', name: 'Concert' }])).title).toBe('Concert');
  });

  test('matches the script type case-insensitively', () => {
    expect(
      meta(`<script type="Application/LD+JSON">${JSON.stringify({ '@type': 'Article', headline: 'Caps' })}</script>`)
        .title,
    ).toBe('Caps');
  });
});

describe('normalization', () => {
  test('trims, collapses whitespace, and decodes entities that survived into strings', () => {
    const head = `<meta property="og:title" content="  Fish   &amp;amp;\n  Chips  ">${article({ description: 'Tom &amp; Jerry &#8212; &quot;live&quot;' })}`;
    const m = meta(head);
    expect(m.title).toBe('Fish & Chips');
    expect(m.description).toBe('Tom & Jerry — "live"');
  });

  test('decoding never turns text into markup', () => {
    const m = meta(article({ headline: '&lt;img src=x onerror=alert(1)&gt; <b>bold</b>' }));
    expect(m.title).toBe('<img src=x onerror=alert(1)> <b>bold</b>');
  });

  test('leaves ampersands that are not entities alone', () => {
    expect(meta('<meta property="og:title" content="R&D at AT&T, a=1&copy=2">').title).toBe('R&D at AT&T, a=1&copy=2');
  });
});

describe('captureLink', () => {
  test('returns metadata and warnings without modifying the document', () => {
    const d = doc(`<title>Hi</title>${article({ headline: 'Hello' })}`, '<p>body</p>');
    const before = d.documentElement.outerHTML;
    const capture = captureLink(d, { pageUrl: PAGE });
    expect(capture.metadata.title).toBe('Hello');
    expect(capture.warnings).toEqual([]);
    expect(d.documentElement.outerHTML).toBe(before);
  });
});
