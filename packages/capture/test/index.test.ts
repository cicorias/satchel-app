import { expect, test } from 'vitest';
import { version } from '../src/index.ts';

test('exports a version', () => {
  expect(version).toMatch(/^\d+\.\d+\.\d+$/);
});
