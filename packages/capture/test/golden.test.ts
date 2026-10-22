// Golden fixtures (spec §12.4): fixtures/pages/<name>/ with input.html, url.txt, and expected outputs.
// Link mode checks expected-metadata.json. Page mode (expected.md) arrives with the page pipeline.

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { parseHTML } from 'linkedom';
import { describe, expect, test } from 'vitest';
import { captureLink } from '../src/index.ts';

const root = new URL('../../../fixtures/pages/', import.meta.url);
const read = (name: string, file: string) => readFileSync(new URL(`${name}/${file}`, root), 'utf8');
const fixtures = readdirSync(root, { withFileTypes: true })
  .filter((entry) => entry.isDirectory() && existsSync(new URL(`${entry.name}/expected-metadata.json`, root)))
  .map((entry) => entry.name)
  .sort();

describe('golden fixtures: link mode', () => {
  test('there is at least one', () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  test.each(fixtures)('%s', (name) => {
    const doc = parseHTML(read(name, 'input.html')).document as unknown as Document;
    const { metadata } = captureLink(doc, { pageUrl: read(name, 'url.txt').trim() });
    expect(metadata).toStrictEqual(JSON.parse(read(name, 'expected-metadata.json')));
  });
});
