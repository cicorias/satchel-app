// The browser-specific operations the popup needs (spec §9.1.3). Each browser implements them in this folder;
// nothing outside it (and the entry points) may call chrome.* or browser.*.

import type { CapturedItem } from '@satchel/capture';
import type { ClientId, Item, ItemKind } from '@satchel/model';

/** What to do when a page is saved over a saved page (FR-6). */
export type ExistingPage = 'ask' | 'replace' | 'keep';

export type SaveResult =
  | { status: 'saved'; item: Item; synced: boolean; syncError?: string }
  /** A page is already saved for this URL: ask "Replace saved copy?", then save again with `replace` or `keep`. */
  | { status: 'confirm-replace' }
  | { status: 'error'; message: string; code?: string };

export interface PlatformAdapter {
  /** The client ID saves from this browser carry. */
  readonly client: ClientId;
  /** Wakes the native side up before a save (Safari; ADR-0007 addendum). */
  warmUp(): Promise<void>;
  save(captured: CapturedItem, existingPage?: ExistingPage): Promise<SaveResult>;
  /** Known tags, most used first, for autocomplete. */
  tags(prefix?: string): Promise<string[]>;
  /** Whether this URL is already saved. */
  status(url: string): Promise<{ saved: boolean; kind?: ItemKind }>;
}
