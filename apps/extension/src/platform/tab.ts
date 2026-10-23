// The active tab, and capturing it: inject the capture engine (entrypoints/capture.ts) on the user's action, then run
// captureLink or capturePage in the page and build the Item there, so the popup never loads the engine itself.

import type * as Capture from '@satchel/capture';
import type { CapturedItem } from '@satchel/capture';
import type { ClientId } from '@satchel/model';

export interface ActiveTab {
  id: number;
  title?: string;
  url?: string;
}

export type CaptureMode = 'link' | 'page';

export interface CaptureExtras {
  client: ClientId;
  version: string;
  tags: string[];
  note?: string;
}

export type CaptureOutcome =
  | { ok: true; captured: CapturedItem; warnings: string[] }
  | { ok: false; message: string; tooLarge?: boolean };

export async function activeTab(): Promise<ActiveTab | undefined> {
  const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
  if (tab?.id === undefined) return undefined;
  return { id: tab.id, ...(tab.title && { title: tab.title }), ...(tab.url && { url: tab.url }) };
}

/** Runs inside the page, so it may only use its arguments and the page's globals. */
async function runCapture(mode: CaptureMode, extras: CaptureExtras): Promise<CaptureOutcome> {
  const api = (globalThis as unknown as { SatchelCapture?: typeof Capture }).SatchelCapture;
  if (!api) return { ok: false, message: 'The capture engine didn’t load in this page.' };
  const pageUrl = location.href;
  try {
    const capture =
      mode === 'page' ? await api.capturePage(document, { pageUrl }) : api.captureLink(document, { pageUrl });
    const captured = api.itemFromCapture(capture, { pageUrl, ...extras });
    return { ok: true, captured, warnings: capture.warnings };
  } catch (error) {
    const name = error instanceof Error ? error.name : '';
    if (name === 'UnsupportedUrlError') return { ok: false, message: 'Only web pages (http and https) can be saved.' };
    if (name === 'PageTooLargeError') {
      return { ok: false, tooLarge: true, message: 'This page is too large to save as a page. Save it as a link.' };
    }
    return { ok: false, message: `The page couldn’t be captured: ${String(error)}` };
  }
}

export async function captureTab(tabId: number, mode: CaptureMode, extras: CaptureExtras): Promise<CaptureOutcome> {
  try {
    await browser.scripting.executeScript({ target: { tabId }, files: ['/capture.js'] });
    const [result] = await browser.scripting.executeScript({
      target: { tabId },
      func: runCapture,
      args: [mode, extras],
    });
    return (result?.result as CaptureOutcome | undefined) ?? { ok: false, message: 'The page returned nothing.' };
  } catch (error) {
    return { ok: false, message: `Satchel can’t read this page: ${String(error)}` };
  }
}
