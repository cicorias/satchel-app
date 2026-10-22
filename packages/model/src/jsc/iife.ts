// The JavaScriptCore build (ADR-0020): bare JSC has no URL, URLSearchParams, or TextEncoder, so this entry adds
// them before the model loads. Browser bundles use packages/model/src/iife.ts and the native APIs instead.
// Shared vectors check that both builds produce identical normalized URLs and IDs.

import 'core-js/actual/url';
import 'core-js/actual/url-search-params';
import './text-encoder.ts';
import * as api from '../index.ts';

(globalThis as Record<string, unknown>).SatchelModel = api;
