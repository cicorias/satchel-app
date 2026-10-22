import { readFileSync } from 'node:fs';
import { itemIdFor, normalizedUrlFor, UnsupportedUrlError } from '@satchel/model';
import { parseHTML } from 'linkedom';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { parse as parseYaml } from 'yaml';
import { annotateCodeLanguages } from '../src/code.ts';
import { contentExcerpt, linkExcerpt } from '../src/excerpt.ts';
import { yamlScalar } from '../src/frontmatter.ts';
import { postprocessContent, preprocessImages } from '../src/images.ts';
import {
  captureLink,
  capturePage,
  collectImages,
  countWords,
  ENGINE,
  formatFrontmatter,
  htmlToMarkdown,
  PageTooLargeError,
  readingStats,
} from '../src/index.ts';

const PAGE = 'https://www.example.com/posts/kayak?utm_source=feed';
const NOW = new Date('2026-10-22T12:00:00.000Z');
const PROSE = Array.from(
  { length: 8 },
  (_, i) =>
    `<p>Paragraph ${i + 1} explains how the river trip went, which gear held up, and what we would pack differently next time we paddle.</p>`,
).join('');

const doc = (body: string, head = '<title>Kayaking the Upper River</title>') =>
  parseHTML(`<!doctype html><html lang="en"><head>${head}</head><body>${body}</body></html>`)
    .document as unknown as Document;

const frontmatterOf = (markdown: string) => parseYaml(markdown.split('\n---\n')[0]?.replace(/^---\n/, '') ?? '');

describe('preprocessImages (§4.4 step 2)', () => {
  const run = (body: string, base = 'https://example.com/a/') => {
    const d = doc(body);
    preprocessImages(d, base);
    return d;
  };

  test('promotes lazy-load attributes', () => {
    const d = run(
      '<img src="data:image/gif;base64,R0lGOD" data-src="/real.jpg"><img data-lazy-src="b.jpg"><img data-original="//cdn.example.com/c.jpg">',
    );
    expect(Array.from(d.querySelectorAll('img')).map((i) => i.getAttribute('src'))).toEqual([
      'https://example.com/real.jpg',
      'https://example.com/a/b.jpg',
      'https://cdn.example.com/c.jpg',
    ]);
  });

  test('picks the largest srcset candidate, including data-srcset', () => {
    const d = run('<img src="s.jpg" data-srcset="m.jpg 800w, l.jpg 1600w, xs.jpg 200w">');
    expect(d.querySelector('img')?.getAttribute('src')).toBe('https://example.com/a/l.jpg');
    expect(d.querySelector('img')?.hasAttribute('srcset')).toBe(false);
  });

  test('picks the largest candidate across <picture> sources', () => {
    const d = run(
      '<picture><source type="image/avif" srcset="a-640.avif 640w, a-1280.avif 1280w"><source srcset="a-2000.webp 2000w"><img src="a.jpg"></picture>',
    );
    expect(d.querySelector('img')?.getAttribute('src')).toBe('https://example.com/a/a-2000.webp');
    expect(d.querySelectorAll('source').length).toBe(0);
  });

  test('density descriptors pick the highest density', () => {
    expect(run('<img srcset="a.jpg 1x, a@3x.jpg 3x, a@2x.jpg 2x">').querySelector('img')?.getAttribute('src')).toBe(
      'https://example.com/a/a@3x.jpg',
    );
  });

  test('a <noscript> image replaces the placeholder before it', () => {
    const d = run(
      '<img src="data:image/gif;base64,R0lGOD" data-src="lazy.jpg"><noscript><img src="real.jpg" alt="Real"></noscript>',
    );
    expect(d.querySelectorAll('img').length).toBe(1);
    expect(d.querySelector('img')?.getAttribute('src')).toBe('https://example.com/a/real.jpg');
    expect(d.querySelector('img')?.getAttribute('alt')).toBe('Real');
    expect(d.querySelector('noscript')).toBeNull();
  });

  test('a <noscript> image without a placeholder is recovered in place', () => {
    const d = run('<p>Before</p><noscript><img src="only.jpg"></noscript><p>After</p>');
    expect(d.querySelector('img')?.getAttribute('src')).toBe('https://example.com/a/only.jpg');
  });

  test('drops non-http(s) sources but keeps data: images', () => {
    const d = run('<img src="javascript:alert(1)"><img src="data:image/png;base64,AAAA">');
    const srcs = Array.from(d.querySelectorAll('img')).map((i) => i.getAttribute('src'));
    expect(srcs).toEqual([null, 'data:image/png;base64,AAAA']);
  });
});

describe('postprocessContent (§4.4 step 4)', () => {
  const run = (html: string) => {
    const warnings: string[] = [];
    const out = postprocessContent(doc(''), html, 'https://example.com/a/', warnings);
    return { out, warnings };
  };

  test('makes links absolute, keeps mailto: and tel:, and strips dangerous hrefs', () => {
    const { out } = run(
      '<a href="../b">rel</a><a href="mailto:x@example.com">m</a><a href="tel:+15550100">t</a><a href="javascript:alert(1)">j</a><a href="data:text/html,x">d</a>',
    );
    expect(out).toBe(
      '<a href="https://example.com/b">rel</a><a href="mailto:x@example.com">m</a><a href="tel:+15550100">t</a><a>j</a><a>d</a>',
    );
  });

  test('drops tracking pixels', () => {
    const { out } = run(
      '<img src="/p.gif" width="1" height="1"><img src="/q.gif" width="2"><img src="/ok.png" width="600">',
    );
    expect(out).toBe('<img src="https://example.com/ok.png" width="600">');
  });

  test('keeps data: images under 8 KB and drops larger ones with a warning', () => {
    const small = `data:image/png;base64,${'A'.repeat(1000)}`;
    const large = `data:image/png;base64,${'A'.repeat(12000)}`;
    const { out, warnings } = run(`<img src="${small}"><img src="${large}">`);
    expect(out).toBe(`<img src="${small}">`);
    expect(warnings).toEqual(['dropped-large-data-image']);
  });
});

describe('annotateCodeLanguages', () => {
  test('carries GitHub and Sphinx wrapper languages to data-lang, and ignores GitHub\'s "md" README box', () => {
    const d = doc(`<div class="Box md"><article class="markdown-body">
      <div class="highlight highlight-source-rust"><pre>fn main() {}</pre></div>
      <div class="highlight highlight-text-md"><pre># x</pre></div>
      <div class="highlight-console notranslate"><div class="highlight"><pre>$ ls</pre></div></div>
      <div class="highlight-default"><pre>plain</pre></div>
      <pre data-lang="go">kept</pre></article></div>`);
    annotateCodeLanguages(d);
    expect(Array.from(d.querySelectorAll('pre')).map((p) => p.getAttribute('data-lang'))).toEqual([
      'rust',
      'md',
      'console',
      null,
      'go',
    ]);
    expect(d.querySelector('.Box')?.classList.contains('md')).toBe(false);
  });
});

describe('body excerpt (§4.3)', () => {
  const long = 'This opening paragraph is comfortably longer than eighty characters, so it qualifies as an excerpt.';

  test('link mode searches article, then main, then body', () => {
    expect(linkExcerpt(doc(`<p>${long} (body)</p><main><p>${long} (main)</p></main>`))).toBe(`${long} (main)`);
    expect(linkExcerpt(doc(`<main><p>${long} (main)</p></main><article><p>${long} (article)</p></article>`))).toBe(
      `${long} (article)`,
    );
    expect(linkExcerpt(doc(`<div><p>${long} (body)</p></div>`))).toBe(`${long} (body)`);
  });

  test('link mode skips short paragraphs, chrome, and consent or promo containers', () => {
    const body = `<header><p>${long} header</p></header><nav><p>${long} nav</p></nav><aside><p>${long} aside</p></aside>
      <div class="cookie-banner"><p>${long} cookie</p></div><section id="newsletter-signup"><p>${long} newsletter</p></section>
      <p>Too short to count.</p><footer><p>${long} footer</p></footer><p>${long} real</p>`;
    expect(linkExcerpt(doc(body))).toBe(`${long} real`);
  });

  test('link mode fills a missing description', () => {
    expect(captureLink(doc(`<article><p>${long}</p></article>`), { pageUrl: PAGE }).metadata.description).toBe(long);
  });

  test('page mode takes the first long paragraph of the extracted content', () => {
    const holder = doc(`<p>short</p><p>${long}</p>`).body;
    expect(contentExcerpt(holder)).toBe(long);
  });

  test('collapses whitespace', () => {
    expect(linkExcerpt(doc(`<p>  ${long.replace(/ /g, '\n   ')}  </p>`))).toBe(long);
  });
});

describe('frontmatter (§5)', () => {
  test.each([
    ['https://example.com/a?b=1&c=2', 'https://example.com/a?b=1&c=2'],
    ['defuddle@0.19.4 + turndown@7.2.4', 'defuddle@0.19.4 + turndown@7.2.4'],
    ['cloudkit', 'cloudkit'],
    ['key: value', '"key: value"'],
    ['ends with colon:', '"ends with colon:"'],
    ['a #comment', '"a #comment"'],
    ['#hashtag', '"#hashtag"'],
    ['- dash', '"- dash"'],
    ['[bracket', '"[bracket"'],
    ['*star', '"*star"'],
    ['yes', '"yes"'],
    ['Null', '"Null"'],
    ['2026', '"2026"'],
    ['.5', '".5"'],
    [' padded', '" padded"'],
    ['', '""'],
    ['line\nbreak', '"line\\nbreak"'],
  ])('yamlScalar(%j) = %s', (input, expected) => {
    expect(yamlScalar(input)).toBe(expected);
    expect(parseYaml(`v: ${yamlScalar(input)}`).v).toBe(input);
  });

  test('round-trips every field through a YAML parser', () => {
    const fields = {
      id: 'u_445740458d1bf9f96939cbc420e6973c',
      type: 'page' as const,
      title: 'Colons: "quotes", #hashes, and \\ backslashes',
      url: 'https://example.com/a?x=1#!/route',
      canonical: 'https://example.com/a',
      site: 'Example: The Site',
      author: "O'Neill, Shah",
      published: '2026-09-30T00:00:00.000Z',
      saved: '2026-10-21T14:03:22.000Z',
      updated: '2026-10-21T14:03:22.000Z',
      description: 'Line one line two — “smart” quotes',
      image: 'https://example.com/i.png',
      tags: ['swift', 'yes', 'c#', 'two words'],
      source: 'chrome',
      engine: 'defuddle@0.19.4 + turndown@7.2.4',
    };
    const yaml = formatFrontmatter(fields);
    expect(yaml.startsWith('---\nid: u_445740458d1bf9f96939cbc420e6973c\ntype: page\n')).toBe(true);
    const parsed = parseYaml(yaml.replace(/^---\n|---\n$/g, ''), { schema: 'core' });
    expect({ ...parsed, published: fields.published, saved: fields.saved, updated: fields.updated }).toEqual(fields);
  });
});

describe('collectImages and countWords', () => {
  test('collects images in order, once per URL, unescaping alt and URL', () => {
    const md =
      '![A](https://e.com/1.png "t") text ![](https://e.com/2.png) ![\\[x\\]](https://e.com/a_\\(1\\).png) ![dup](https://e.com/1.png) ![sp](<https://e.com/a b.png>)';
    expect(collectImages(md)).toEqual([
      { originalUrl: 'https://e.com/1.png', alt: 'A', status: 'remote' },
      { originalUrl: 'https://e.com/2.png', status: 'remote' },
      { originalUrl: 'https://e.com/a_(1).png', alt: '[x]', status: 'remote' },
      { originalUrl: 'https://e.com/a b.png', alt: 'sp', status: 'remote' },
    ]);
  });

  test('counts words of the text, not of the syntax', () => {
    expect(
      countWords(
        '## Heading two\n\n- [link text](https://e.com/x) and **bold**\n\n```js\ncode here\n```\n\n| a | b |\n| --- | --- |',
      ),
    ).toBe(
      // Heading two (2) + link text and bold (4) + code here (2) + a b (2)
      10,
    );
  });
});

test('counts Han and kana characters as words, read at 500 a minute', () => {
  expect(readingStats('今日は晴れです。 Tokyo trip')).toEqual({ wordCount: 9, readingMinutes: 1 });
  expect(readingStats('한국어는 띄어쓰기를 합니다').wordCount).toBe(3);
  expect(readingStats('あ'.repeat(1000)).readingMinutes).toBe(2);
});

test('numbered headings are not escaped', () => {
  expect(htmlToMarkdown('<h2>1. Level the bed</h2><h3>- dash</h3><p>1. but this is escaped</p>')).toBe(
    '## 1. Level the bed\n\n### - dash\n\n1\\. but this is escaped',
  );
});

describe('capturePage (§4.4)', () => {
  afterEach(() => vi.unstubAllGlobals());

  const article = (extra = '') =>
    doc(
      `<header><nav><a href="/">Home</a> <a href="/about">About</a></nav></header>
       <article><h1>Kayaking the Upper River</h1>${PROSE}<figure><img src="/img/river.jpg" alt="The river" title="Upper falls"><figcaption>The upper falls at dawn</figcaption></figure>${extra}</article>
       <footer><p>© 2026 Example Outdoors. All rights reserved. Subscribe to our newsletter for more trip reports.</p></footer>`,
      '<title>Kayaking the Upper River | Example Outdoors</title><meta property="og:title" content="Kayaking the Upper River"><link rel="canonical" href="https://example.com/posts/kayak">',
    );

  test('produces frontmatter plus a body that starts with the title heading', async () => {
    const result = await capturePage(article(), { pageUrl: PAGE, now: NOW });
    expect(result.bodyMarkdown.startsWith('# Kayaking the Upper River\n\nParagraph 1 explains')).toBe(true);
    expect(result.bodyMarkdown).toContain(
      '![The river](https://www.example.com/img/river.jpg "Upper falls")\n\n*The upper falls at dawn*',
    );
    expect(result.bodyMarkdown).not.toContain('Home');
    expect(result.markdown).toBe(`${result.markdown.split('\n---\n')[0]}\n---\n\n${result.bodyMarkdown}`);
    expect(result.markdown.endsWith('\n')).toBe(true);
    expect(result.markdown.endsWith('\n\n')).toBe(false);
    expect(result.warnings).toEqual([]);
  });

  test('frontmatter is valid YAML with the §5 fields', async () => {
    const result = await capturePage(article(), { pageUrl: PAGE, now: NOW });
    const fm = frontmatterOf(result.markdown);
    expect(fm).toMatchObject({
      id: itemIdFor(normalizedUrlFor(PAGE, 'https://example.com/posts/kayak')),
      type: 'page',
      title: 'Kayaking the Upper River',
      url: PAGE,
      canonical: 'https://example.com/posts/kayak',
      site: 'example.com',
      tags: [],
      engine: 'defuddle@0.19.4 + turndown@7.2.4',
    });
    expect(new Date(fm.saved).toISOString()).toBe(NOW.toISOString());
    expect(fm.description).toMatch(/^Paragraph 1 explains/);
  });

  test('collects images, counts words, and reports the engine', async () => {
    const result = await capturePage(article(), { pageUrl: PAGE, now: NOW });
    expect(result.images).toEqual([
      { originalUrl: 'https://www.example.com/img/river.jpg', alt: 'The river', status: 'remote' },
    ]);
    expect(result.stats.wordCount).toBeGreaterThan(150);
    expect(result.stats.readingMinutes).toBe(Math.ceil(result.stats.wordCount / 230));
    expect(result.engine).toEqual({ extractor: 'defuddle@0.19.4', converter: 'turndown@7.2.4' });
  });

  test('never modifies the live document', async () => {
    const d = article('<img data-src="/lazy.jpg"><noscript><img src="/ns.jpg"></noscript>');
    const before = d.documentElement.outerHTML;
    await capturePage(d, { pageUrl: PAGE, now: NOW });
    expect(d.documentElement.outerHTML).toBe(before);
  });

  test('drops a first heading that repeats the title, but keeps a different one', async () => {
    const page = (heading: string) =>
      capturePage(
        doc(
          `<article><h2>${heading}</h2>${PROSE}</article>`,
          '<title>Kayaking the Upper River & Back | Example</title>',
        ),
        {
          pageUrl: PAGE,
          now: NOW,
        },
      );
    expect((await page('Kayaking the Upper River and Back')).bodyMarkdown).toMatch(
      /^# Kayaking the Upper River & Back \| Example\n\nParagraph 1/,
    );
    expect((await page('Kayaking the Upper River')).bodyMarkdown).toMatch(/^# [^\n]+\n\nParagraph 1/);
    expect((await page('Gear we took')).bodyMarkdown).toMatch(/^# [^\n]+\n\n## Gear we took\n/);
  });

  test('converts only the selection when one is given', async () => {
    const result = await capturePage(article(), {
      pageUrl: PAGE,
      now: NOW,
      selectionHtml: '<p>Just <strong>this</strong> part, with a <a href="/gear">link</a>.</p>',
    });
    expect(result.bodyMarkdown).toBe(
      '# Kayaking the Upper River\n\nJust **this** part, with a [link](https://www.example.com/gear).\n',
    );
  });

  test('falls back to the page body with a warning when extraction finds under 50 words', async () => {
    const result = await capturePage(doc('<main><p>Only a few words here.</p></main><aside>Sidebar</aside>'), {
      pageUrl: PAGE,
      now: NOW,
    });
    expect(result.warnings).toContain('low-confidence-extraction');
    expect(result.bodyMarkdown).toBe('# Kayaking the Upper River\n\nOnly a few words here.\n');
  });

  test('never fetches anything (Defuddle runs with useAsync: false)', async () => {
    const fetch = vi.fn(() => Promise.reject(new Error('network')));
    vi.stubGlobal('fetch', fetch);
    await capturePage(doc(''), { pageUrl: 'https://x.com/someone/status/123', now: NOW });
    await capturePage(article(), { pageUrl: PAGE, now: NOW });
    expect(fetch).not.toHaveBeenCalled();
  });

  test('throws PageTooLargeError past 10 MB', async () => {
    const huge = `<p>${'word '.repeat(2_200_000)}</p>`;
    await expect(capturePage(doc(`<article>${huge}</article>`), { pageUrl: PAGE, now: NOW })).rejects.toThrow(
      PageTooLargeError,
    );
  });

  test('rejects a non-http(s) page URL', async () => {
    await expect(capturePage(article(), { pageUrl: 'file:///tmp/a.html', now: NOW })).rejects.toThrow(
      UnsupportedUrlError,
    );
  });

  test('ENGINE matches the installed versions', () => {
    const version = (name: string) =>
      JSON.parse(readFileSync(new URL(`../node_modules/${name}/package.json`, import.meta.url), 'utf8')).version;
    expect(ENGINE).toEqual({
      extractor: `defuddle@${version('defuddle')}`,
      converter: `turndown@${version('turndown')}`,
    });
  });
});
