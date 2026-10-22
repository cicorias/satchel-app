// The JavaScriptCore bundle (ADR-0020) must give exactly the results the native URL API gives. Each bundle runs
// in a fresh global: the browser bundle with Node's URL and TextEncoder, and the JSC bundle with neither, so it
// has to rely on its own polyfills, as it does in JavaScriptCore.

import { readFileSync } from 'node:fs';
import { createContext, runInContext } from 'node:vm';
import { expect, test } from 'vitest';

const inputs: [string, string | null][] = JSON.parse(readFileSync(new URL('url-inputs.json', import.meta.url), 'utf8'));
const run = `JSON.stringify(INPUTS.map(([page, canonical]) => {
  try { const n = SatchelModel.normalizedUrlFor(page, canonical ?? undefined); return [n, SatchelModel.itemIdFor(n)]; }
  catch (e) { return ['error: ' + e.name]; }
}))`;

function results(bundle: string, globals: Record<string, unknown>): unknown {
  const sandbox: Record<string, unknown> = { INPUTS: inputs, ...globals };
  sandbox.globalThis = sandbox;
  const context = createContext(sandbox);
  runInContext(readFileSync(new URL(`../dist/${bundle}`, import.meta.url), 'utf8'), context);
  return JSON.parse(runInContext(run, context) as string);
}

test('model.jsc.iife.js without URL or TextEncoder matches the native-URL bundle on every input', () => {
  expect(runInContext('typeof URL + typeof TextEncoder', createContext({}))).toBe('undefinedundefined');
  const native = results('model.iife.js', { URL, URLSearchParams, TextEncoder });
  const jsc = results('model.jsc.iife.js', {});
  expect(inputs.length).toBeGreaterThan(100);
  expect(jsc).toEqual(native);
});
