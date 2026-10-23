// Picks this build's adapter. Chrome and Edge get theirs (IndexedDB outbox → CloudKit Web Services) in Phase 2.

import { safari } from './safari.ts';
import type { PlatformAdapter } from './types.ts';

const chromium: PlatformAdapter = {
  get client() {
    return import.meta.env.EDGE ? 'edge' : 'chrome';
  },
  warmUp: async () => {},
  save: async () => ({ status: 'error', message: 'Saving from Chrome and Edge arrives in Phase 2.' }),
  tags: async () => [],
  status: async () => ({ saved: false }),
};

export const platform: PlatformAdapter = import.meta.env.SAFARI ? safari : chromium;
export { activeTab, type CaptureMode, captureTab } from './tab.ts';
export type { ExistingPage, PlatformAdapter, SaveResult } from './types.ts';
