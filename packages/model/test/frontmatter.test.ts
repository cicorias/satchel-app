import { describe, expect, test } from 'vitest';
import { frontmatterFor, type Item, markdownFile } from '../src/index.ts';

const link: Item = {
  schemaVersion: 1,
  id: 'u_445740458d1bf9f96939cbc420e6973c',
  kind: 'link',
  url: 'https://www.example.com/articles/hello-world/?utm_source=newsletter',
  canonicalUrl: 'https://example.com/articles/hello-world',
  normalizedUrl: 'https://example.com/articles/hello-world',
  title: 'Hello: World',
  description: 'A first post.',
  siteName: 'Example',
  tags: ['swift', 'ios'],
  note: 'read later',
  createdAt: '2026-10-22T16:40:27.512Z',
  updatedAt: '2026-10-23T09:00:00.000Z',
  metadataStatus: 'complete',
  source: { client: 'ios-share', version: '2026.10.0' },
};

describe('markdownFile', () => {
  test('a link exports frontmatter, its title, and its description', () => {
    expect(markdownFile(link)).toBe(
      [
        '---',
        'id: u_445740458d1bf9f96939cbc420e6973c',
        'type: link',
        'title: "Hello: World"',
        'url: https://www.example.com/articles/hello-world/?utm_source=newsletter',
        'canonical: https://example.com/articles/hello-world',
        'site: "Example"',
        'saved: 2026-10-22T16:40:27.512Z',
        'updated: 2026-10-23T09:00:00.000Z',
        'description: "A first post."',
        'tags: [swift, ios]',
        'source: ios-share',
        '---',
        '',
        '# Hello: World',
        '',
        'A first post.',
        '',
      ].join('\n'),
    );
  });

  test('a page exports its stored body after frontmatter with the engine', () => {
    const page: Item = {
      ...link,
      kind: 'page',
      capturedAt: link.updatedAt,
      page: { wordCount: 3, readingMinutes: 1, engine: 'defuddle@0.19.4 + turndown@7.2.4', images: [] },
    };
    const file = markdownFile(page, '# Hello: World\n\nBody.\n');
    expect(file).toContain('type: page\n');
    expect(file).toContain('engine: defuddle@0.19.4 + turndown@7.2.4\n---\n\n# Hello: World\n\nBody.\n');
  });

  test('omits empty optional fields', () => {
    const bare: Item = { ...link, tags: [] };
    delete bare.description;
    delete bare.siteName;
    expect(frontmatterFor(bare)).not.toHaveProperty('description');
    expect(markdownFile(bare)).toContain('tags: []\n');
    expect(markdownFile(bare).endsWith('---\n\n# Hello: World\n')).toBe(true);
  });
});
