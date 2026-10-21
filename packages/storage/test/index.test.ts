import { expectTypeOf, test } from 'vitest';
import type { ProviderId } from '../src/index.ts';

test('cloudkit is a provider id', () => {
  expectTypeOf<'cloudkit'>().toExtend<ProviderId>();
});
