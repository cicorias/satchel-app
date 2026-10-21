import { defineConfig } from 'tsup';

// IIFE bundle for WKWebView / Share Extension preprocessing: exposes globalThis.SatchelRender.
export default defineConfig({
  entry: { render: 'src/iife.ts' },
  format: ['iife'],
  outExtension: () => ({ js: '.iife.js' }),
  platform: 'browser',
  target: 'safari18',
  minify: true,
  clean: true,
});
