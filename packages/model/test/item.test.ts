import { readdirSync, readFileSync } from 'node:fs';
import { Ajv2020 } from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { describe, expect, test } from 'vitest';
import {
  CLIENT_IDS,
  IMAGE_REF_SHAPE,
  ITEM_SHAPE,
  ITEM_SOURCE_SHAPE,
  type Item,
  PAGE_INFO_SHAPE,
  SCHEMA_VERSION,
} from '../src/index.ts';

const schema = JSON.parse(readFileSync(new URL('../schema/item.schema.json', import.meta.url), 'utf8'));
const fixturesDir = new URL('../../../fixtures/model/', import.meta.url);
const fixtures = readdirSync(fixturesDir)
  .filter((name) => name.endsWith('.json'))
  .map((name) => ({ name, text: readFileSync(new URL(name, fixturesDir), 'utf8') }));

const ajv = new Ajv2020({ allErrors: true, strict: true });
addFormats.default(ajv);
const validate = ajv.compile<Item>(schema);

function decode(text: string): Item {
  const value: unknown = JSON.parse(text);
  if (!validate(value)) throw new Error(ajv.errorsText(validate.errors));
  return value;
}

const encode = (item: Item) => JSON.stringify(item);

describe('contract fixtures', () => {
  test('there are fixtures for a link, a page, and unknown fields', () => {
    expect(fixtures.map((f) => f.name).sort()).toEqual(['link-minimal.json', 'page-full.json', 'unknown-fields.json']);
  });

  test.each(fixtures)('$name validates against the schema', ({ text }) => {
    expect(() => decode(text)).not.toThrow();
  });

  test.each(fixtures)('$name round-trips losslessly, keeping key order and unknown fields', ({ text }) => {
    const reencoded = encode(decode(text));
    expect(JSON.parse(reencoded)).toStrictEqual(JSON.parse(text));
    expect(reencoded).toBe(JSON.stringify(JSON.parse(text)));
  });

  test('unknown fields survive at every level', () => {
    const text = fixtures.find((f) => f.name === 'unknown-fields.json')?.text ?? '';
    expect(JSON.parse(encode(decode(text)))).toMatchObject({
      readingProgress: { fraction: 0.42, updatedAt: '2026-10-22T11:00:00.000Z' },
      'x-experiment': null,
      source: { build: 4211 },
      page: { images: [{ width: 640, dominantColor: '#336699' }], outline: [{ level: 2, text: 'Introduction' }] },
    });
  });
});

describe('schema matches the TypeScript types', () => {
  const shapes = [
    ['Item', ITEM_SHAPE, schema],
    ['Item.source', ITEM_SOURCE_SHAPE, schema.properties.source],
    ['Item.page', PAGE_INFO_SHAPE, schema.properties.page],
    ['ImageRef', IMAGE_REF_SHAPE, schema.$defs.imageRef],
  ] as const;

  test.each(shapes)('%s has the same properties and required list', (_, shape, node) => {
    const entries = Object.entries(shape);
    expect(Object.keys(node.properties).sort()).toEqual(entries.map(([k]) => k).sort());
    expect([...node.required].sort()).toEqual(
      entries
        .filter(([, required]) => required)
        .map(([k]) => k)
        .sort(),
    );
  });

  test('enums and constants match', () => {
    expect(schema.properties.schemaVersion.const).toBe(SCHEMA_VERSION);
    expect(schema.properties.source.properties.client.enum).toEqual([...CLIENT_IDS]);
  });
});

describe('schema rejects malformed items', () => {
  const base = JSON.parse(fixtures.find((f) => f.name === 'link-minimal.json')?.text ?? '{}');
  const cases: [string, Record<string, unknown>][] = [
    ['an id that is not u_ + 32 lowercase hex', { id: 'u_ABC' }],
    ['a non-http URL', { url: 'ftp://example.com/file' }],
    ['an unknown kind', { kind: 'video' }],
    ['a future schemaVersion', { schemaVersion: 2 }],
    ['an uppercase tag', { tags: ['Swift'] }],
    ['an untrimmed tag', { tags: [' swift'] }],
    ['a duplicate tag', { tags: ['swift', 'swift'] }],
    ['a timestamp that is not ISO 8601', { createdAt: 'yesterday' }],
    ['an unknown client', { source: { client: 'firefox', version: '1' } }],
    ['a page without images', { kind: 'page', page: { wordCount: 1, readingMinutes: 1, engine: 'x' } }],
  ];

  test.each(cases)('%s', (_, patch) => {
    expect(validate({ ...base, ...patch })).toBe(false);
  });

  test('a missing required field', () => {
    const { title: _, ...withoutTitle } = base;
    expect(validate(withoutTitle)).toBe(false);
  });

  test('non-ASCII lowercase tags are allowed', () => {
    expect(validate({ ...base, tags: ['café', 'naïve reading'] })).toBe(true);
  });
});
