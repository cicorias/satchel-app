import { expect, test } from 'vitest';
import { SCHEMA_VERSION } from '../src/index.ts';

test('schema version is 1', () => {
  expect(SCHEMA_VERSION).toBe(1);
});
