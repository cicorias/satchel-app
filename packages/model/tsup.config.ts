import { defineConfig } from 'tsup';

// IIFE bundles exposing globalThis.SatchelModel: `model` for pages and web views, `model.jsc` (with URL and
// TextEncoder polyfills) for JavaScriptCore in SatchelKit (ADR-0020), so Swift runs the same normalization,
// ID, and merge code as every other client.
export default defineConfig({
  entry: { model: 'src/iife.ts', 'model.jsc': 'src/jsc/iife.ts' },
  format: ['iife'],
  outExtension: () => ({ js: '.iife.js' }),
  platform: 'neutral',
  target: 'safari18',
  minify: true,
  clean: true,
});
