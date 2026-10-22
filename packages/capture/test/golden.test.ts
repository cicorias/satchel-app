// Golden fixtures (spec §12.4): fixtures/pages/<name>/ with input.html and url.txt, checked against
// expected-metadata.json (link mode, written by hand from §4.2) and expected.md (page mode).
// `mise run test:golden -u` rewrites expected.md from the current output; review that diff before committing.

import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { parseHTML } from 'linkedom';
import { describe, expect, test } from 'vitest';
import { parse as parseYaml } from 'yaml';
import { captureLink, capturePage } from '../src/index.ts';

const root = new URL('../../../fixtures/pages/', import.meta.url);
const NOW = new Date('2026-10-22T12:00:00.000Z');
const UPDATE = process.env.UPDATE_GOLDEN === '1';

const file = (name: string, path: string) => new URL(`${name}/${path}`, root);
const read = (name: string, path: string) => readFileSync(file(name, path), 'utf8');
const load = (name: string) => ({
  doc: parseHTML(read(name, 'input.html')).document as unknown as Document,
  pageUrl: read(name, 'url.txt').trim(),
});
const fixtures = readdirSync(root, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && existsSync(file(entry.name, 'input.html')))
  .map((entry) => entry.name)
  .sort();
const withFile = (path: string) => fixtures.filter((name) => existsSync(file(name, path)));

describe('golden fixtures', () => {
  test('the corpus has at least 20 pages, each with both expectations', () => {
    expect(fixtures.length).toBeGreaterThanOrEqual(20);
    expect(withFile('expected-metadata.json')).toEqual(fixtures);
    if (!UPDATE) expect(withFile('expected.md')).toEqual(fixtures);
  });
});

describe('golden fixtures: link mode', () => {
  test.each(withFile('expected-metadata.json'))('%s', (name) => {
    const { doc, pageUrl } = load(name);
    expect(captureLink(doc, { pageUrl }).metadata).toStrictEqual(JSON.parse(read(name, 'expected-metadata.json')));
  });
});

describe('golden fixtures: page mode', () => {
  test.each(fixtures)('%s', async (name) => {
    const { doc, pageUrl } = load(name);
    const { markdown } = await capturePage(doc, { pageUrl, now: NOW });
    if (UPDATE) writeFileSync(file(name, 'expected.md'), markdown);
    else expect(markdown).toBe(read(name, 'expected.md'));
    // §5: the frontmatter must be valid YAML whose fields match the metadata.
    const frontmatter = parseYaml(markdown.slice(4, markdown.indexOf('\n---\n')), { schema: 'core' });
    expect(frontmatter).toMatchObject({
      type: 'page',
      url: pageUrl,
      title: captureLink(doc, { pageUrl }).metadata.title,
    });
  });
});
