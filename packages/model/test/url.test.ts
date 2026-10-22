import { readdirSync, readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';
import {
  type Item,
  identityUrl,
  itemIdFor,
  normalizedUrlFor,
  normalizeUrl,
  UnsupportedUrlError,
} from '../src/index.ts';

describe('normalizeUrl (§7.2 steps 1–6)', () => {
  test.each([
    // 1. http(s) only
    ['keeps http', 'http://example.com/a', 'http://example.com/a'],
    // 2. scheme and host case, www., default ports
    ['lowercases scheme and host', 'HTTPS://Example.COM/Path', 'https://example.com/Path'],
    ['keeps path case', 'https://example.com/CaseSensitive', 'https://example.com/CaseSensitive'],
    ['strips a leading www.', 'https://www.example.com/a', 'https://example.com/a'],
    ['keeps other subdomains', 'https://www2.example.com/a', 'https://www2.example.com/a'],
    ['strips only the first www.', 'https://www.www.example.com/a', 'https://www.example.com/a'],
    ['drops :443 on https', 'https://example.com:443/a', 'https://example.com/a'],
    ['drops :80 on http', 'http://example.com:80/a', 'http://example.com/a'],
    ['keeps a non-default port', 'https://example.com:8443/a', 'https://example.com:8443/a'],
    ['keeps :80 on https', 'https://example.com:80/a', 'https://example.com:80/a'],
    // 3. fragment
    ['removes a fragment', 'https://example.com/a#section-2', 'https://example.com/a'],
    ['removes an empty fragment', 'https://example.com/a#', 'https://example.com/a'],
    ['keeps a hashbang route', 'https://example.com/#!/inbox/42', 'https://example.com/#!/inbox/42'],
    // 4. tracking parameters
    [
      'removes every utm_ parameter',
      'https://example.com/a?utm_source=x&utm_medium=y&utm_campaign=z&utm_new_thing=1',
      'https://example.com/a',
    ],
    [
      'removes the listed click IDs',
      'https://example.com/a?fbclid=1&gclid=2&dclid=3&msclkid=4&mc_cid=5&mc_eid=6&igshid=7&ref_src=8&_hsenc=9&_hsmi=10&yclid=11',
      'https://example.com/a',
    ],
    [
      'matches tracking keys case-insensitively',
      'https://example.com/a?UTM_Source=x&FBCLID=1',
      'https://example.com/a',
    ],
    ['keeps other parameters', 'https://example.com/a?id=7&utm_source=x', 'https://example.com/a?id=7'],
    [
      'keeps look-alike keys',
      'https://example.com/a?utm=1&ref=2&gclid_x=3',
      'https://example.com/a?gclid_x=3&ref=2&utm=1',
    ],
    ['drops a bare ?', 'https://example.com/a?', 'https://example.com/a'],
    ['drops empty segments', 'https://example.com/a?&b=1&&a=2&', 'https://example.com/a?a=2&b=1'],
    // 5. sort by key, stable for repeated keys
    ['sorts by key', 'https://example.com/a?z=1&a=2&m=3', 'https://example.com/a?a=2&m=3&z=1'],
    ['keeps repeated keys in order', 'https://example.com/a?b=2&a=1&b=1&a=3', 'https://example.com/a?a=1&a=3&b=2&b=1'],
    ['keeps value encoding as written', 'https://example.com/s?q=a+b&r=c%20d', 'https://example.com/s?q=a+b&r=c%20d'],
    ['sorts by the decoded key', 'https://example.com/a?%62=1&a=2', 'https://example.com/a?a=2&%62=1'],
    ['keeps keys without values', 'https://example.com/a?flag&a=1', 'https://example.com/a?a=1&flag'],
    // 6. trailing slash
    ['removes a trailing slash', 'https://example.com/a/', 'https://example.com/a'],
    ['keeps the root path', 'https://example.com/', 'https://example.com/'],
    ['adds the root path to a bare host', 'https://example.com', 'https://example.com/'],
    ['removes the slash before a query', 'https://example.com/a/?x=1', 'https://example.com/a?x=1'],
    // combined
    [
      'applies every rule together',
      'HTTPS://WWW.Example.com:443/Docs/?utm_source=nl&b=2&a=1#top',
      'https://example.com/Docs?a=1&b=2',
    ],
    ['punycodes an IDN host', 'https://www.Bücher.example/a', 'https://xn--bcher-kva.example/a'],
  ])('%s', (_, input, expected) => {
    expect(normalizeUrl(input)).toBe(expected);
  });

  test('is idempotent', () => {
    const once = normalizeUrl('https://www.example.com/a/?utm_source=x&z=1&a=2#frag');
    expect(normalizeUrl(once)).toBe(once);
  });

  test.each([
    'ftp://example.com/a',
    'file:///etc/hosts',
    'javascript:alert(1)',
    'mailto:a@example.com',
    'not a url',
    '',
  ])('rejects %j', (input) => {
    expect(() => normalizeUrl(input)).toThrow(UnsupportedUrlError);
  });
});

describe('identityUrl (§7.2 step 7)', () => {
  test.each([
    ['same host', 'https://example.com/a?x=1', 'https://example.com/a', 'https://example.com/a'],
    ['www and apex', 'https://www.example.com/a', 'https://example.com/a', 'https://example.com/a'],
    ['another subdomain of the same site', 'https://m.example.com/a', 'https://example.com/a', 'https://example.com/a'],
    [
      'a multi-part public suffix',
      'https://news.example.co.uk/a',
      'https://www.example.co.uk/a',
      'https://www.example.co.uk/a',
    ],
    ['a relative canonical', 'https://example.com/a/b?x=1', '/a/b', 'https://example.com/a/b'],
  ])('uses the canonical URL on the same site: %s', (_, page, canonical, expected) => {
    expect(identityUrl(page, canonical)).toBe(expected);
  });

  test.each([
    ['a different site', 'https://example.com/a', 'https://other.org/a'],
    ['a syndication partner', 'https://news.example.co.uk/a', 'https://example.com/a'],
    ['a sibling under a shared public suffix', 'https://alice.github.io/post', 'https://bob.github.io/post'],
    ['a different IP address', 'http://192.168.1.10/a', 'http://192.168.1.11/a'],
    ['a different single-label host', 'http://intranet/a', 'http://wiki/a'],
    ['a non-http canonical', 'https://example.com/a', 'ftp://example.com/a'],
    ['an unparseable canonical', 'https://example.com/a', 'https://exa mple.com/a'],
  ])('falls back to the page URL for %s', (_, page, canonical) => {
    expect(identityUrl(page, canonical)).toBe(page);
  });

  test('uses the page URL when there is no canonical', () => {
    expect(identityUrl('https://example.com/a')).toBe('https://example.com/a');
    expect(identityUrl('https://example.com/a', '')).toBe('https://example.com/a');
  });

  test('accepts the same IP address', () => {
    expect(identityUrl('http://192.168.1.10/a?x=1', 'http://192.168.1.10/a')).toBe('http://192.168.1.10/a');
  });

  test('rejects a non-http page URL', () => {
    expect(() => identityUrl('ftp://example.com/a', 'https://example.com/a')).toThrow(UnsupportedUrlError);
  });
});

describe('itemIdFor', () => {
  test('is u_ + the first 32 hex of SHA-256 over UTF-8', () => {
    // printf '%s' 'https://example.com/articles/hello-world' | shasum -a 256
    expect(itemIdFor('https://example.com/articles/hello-world')).toBe('u_445740458d1bf9f96939cbc420e6973c');
    // SHA-256("") = e3b0c442…
    expect(itemIdFor('')).toBe('u_e3b0c44298fc1c149afbf4c8996fb924');
  });

  test('hashes UTF-8 bytes, not UTF-16 code units', () => {
    // printf '%s' 'https://example.com/café' | shasum -a 256
    expect(itemIdFor('https://example.com/café')).toBe('u_b65dae36fa32fd0db71ab2d585733762');
  });

  test('two captures of the same article converge on one ID', () => {
    const fromNewsletter = normalizedUrlFor(
      'https://www.example.com/articles/hello-world/?utm_source=newsletter#comments',
      'https://example.com/articles/hello-world',
    );
    const fromShare = normalizedUrlFor('https://example.com/articles/hello-world?fbclid=abc');
    expect(itemIdFor(fromNewsletter)).toBe(itemIdFor(fromShare));
  });
});

describe('contract fixtures', () => {
  const dir = new URL('../../../fixtures/model/', import.meta.url);
  const items = readdirSync(dir)
    .filter((name) => name.endsWith('.json'))
    .map((name) => [name, JSON.parse(readFileSync(new URL(name, dir), 'utf8')) as Item] as const);

  test.each(items)('%s has normalizedUrl and id derived from its URLs', (_, item) => {
    expect(normalizedUrlFor(item.url, item.canonicalUrl)).toBe(item.normalizedUrl);
    expect(itemIdFor(item.normalizedUrl)).toBe(item.id);
  });
});
