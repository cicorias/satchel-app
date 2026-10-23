// Safari: every operation is a native message to SafariWebExtensionHandler, which saves through the App Group
// outbox and CloudKit (ADR-0007). Messages and replies are documented on SatchelKit's ExtensionMessageHandler.

import type { CapturedItem } from '@satchel/capture';
import type { Item, ItemKind } from '@satchel/model';
import type { ExistingPage, PlatformAdapter, SaveResult } from './types.ts';

interface NativeReply {
  ok: boolean;
  item?: Item;
  synced?: boolean;
  syncError?: string;
  confirm?: string;
  tags?: string[];
  saved?: boolean;
  kind?: ItemKind;
  error?: string;
  code?: string;
}

// Safari ignores the application ID and talks to the extension's own app.
const send = async (message: Record<string, unknown>): Promise<NativeReply> =>
  (await browser.runtime.sendNativeMessage('application.id', message)) as NativeReply;

const isIOS = () => /iPhone|iPad|iPod/.test(navigator.userAgent) || navigator.maxTouchPoints > 1;

export const safari: PlatformAdapter = {
  get client() {
    return isIOS() ? 'safari-ios' : 'safari-macos';
  },

  async warmUp() {
    await send({ type: 'ping' }).catch(() => undefined);
  },

  async save(captured: CapturedItem, existingPage: ExistingPage = 'ask'): Promise<SaveResult> {
    let reply: NativeReply;
    try {
      reply = await send({ type: 'save', item: captured.item, body: captured.body, existingPage });
    } catch (error) {
      return { status: 'error', message: `Satchel didn't answer: ${String(error)}` };
    }
    if (reply.confirm === 'replace') return { status: 'confirm-replace' };
    if (!reply.ok || !reply.item) {
      return { status: 'error', message: reply.error ?? 'The save failed.', ...(reply.code && { code: reply.code }) };
    }
    return {
      status: 'saved',
      item: reply.item,
      synced: reply.synced === true,
      ...(reply.syncError && { syncError: reply.syncError }),
    };
  },

  async tags(prefix?: string) {
    const reply = await send({ type: 'tags', ...(prefix && { prefix }) }).catch(() => undefined);
    return reply?.tags ?? [];
  },

  async status(url: string) {
    const reply = await send({ type: 'status', url }).catch(() => undefined);
    return { saved: reply?.saved === true, ...(reply?.kind && { kind: reply.kind }) };
  },
};
