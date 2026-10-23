// The popup (spec §9.1.1): Save link (Enter) or Save page for the current tab, with optional tags and a note
// (FR-5), and "Replace saved copy?" when a page is saved over a saved page (FR-6).

import type { CapturedItem } from '@satchel/capture';
import app from '../../../../../config/app.config.json' with { type: 'json' };
import { activeTab, type CaptureMode, captureTab, type ExistingPage, platform } from '../../platform/index.ts';

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const form = $<HTMLFormElement>('save-form');
const saveLink = $<HTMLButtonElement>('save-link');
const savePage = $<HTMLButtonElement>('save-page');
const tagsInput = $<HTMLInputElement>('tags');
const tagOptions = $<HTMLDataListElement>('tag-options');
const note = $<HTMLTextAreaElement>('note');
const confirm = $<HTMLElement>('confirm');
const statusLine = $<HTMLParagraphElement>('status');

let knownTags: string[] = [];
/** The page capture waiting for an answer to "Replace saved copy?". */
let awaitingReplace: CapturedItem | undefined;

const setStatus = (text: string, tone: 'info' | 'ok' | 'error' = 'info') => {
  statusLine.textContent = text;
  statusLine.dataset.tone = tone;
};

const setBusy = (busy: boolean) => {
  saveLink.disabled = busy;
  savePage.disabled = busy;
};

/** Tags are separated by commas or periods (the Share Extension uses the same rule, SatchelKit `TagInput`). */
const TAG_SEPARATOR = /[,.]/;
const enteredTags = () => tagsInput.value.split(TAG_SEPARATOR);

/** Suggestions complete the tag being typed (the text after the last separator). */
function suggestTags() {
  const text = tagsInput.value;
  const parts = text.split(TAG_SEPARATOR);
  const current = (parts.pop() ?? '').trim().toLowerCase();
  const chosen = new Set(parts.map((tag) => tag.trim().toLowerCase()));
  const head = text.slice(0, text.length - (text.split(TAG_SEPARATOR).at(-1) ?? '').length).trimEnd();
  const prefix = head ? `${head} ` : '';
  tagOptions.replaceChildren(
    ...knownTags
      .filter((tag) => tag.startsWith(current) && !chosen.has(tag))
      .slice(0, 8)
      .map((tag) => Object.assign(document.createElement('option'), { value: `${prefix}${tag}` })),
  );
}

async function store(captured: CapturedItem, existingPage: ExistingPage) {
  const result = await platform.save(captured, existingPage);
  switch (result.status) {
    case 'saved': {
      const what = result.item.kind === 'page' ? 'Page' : 'Link';
      setStatus(result.synced ? `${what} saved.` : `${what} saved. It syncs when Satchel can reach iCloud.`, 'ok');
      break;
    }
    case 'confirm-replace':
      awaitingReplace = captured;
      confirm.hidden = false;
      setStatus('');
      break;
    case 'error':
      setStatus(result.message, 'error');
      break;
  }
}

async function save(mode: CaptureMode) {
  const tab = await activeTab();
  if (!tab) return setStatus('There’s no tab to save.', 'error');
  setBusy(true);
  confirm.hidden = true;
  setStatus(mode === 'page' ? 'Capturing the page…' : 'Saving…');
  try {
    const outcome = await captureTab(tab.id, mode, {
      client: platform.client,
      version: app.version,
      tags: enteredTags(),
      note: note.value,
    });
    if (!outcome.ok) return setStatus(outcome.message, 'error');
    await store(outcome.captured, 'ask');
  } finally {
    setBusy(false);
  }
}

async function answerReplace(existingPage: ExistingPage) {
  const captured = awaitingReplace;
  if (!captured) return;
  awaitingReplace = undefined;
  confirm.hidden = true;
  setBusy(true);
  setStatus('Saving…');
  try {
    await store(captured, existingPage);
  } finally {
    setBusy(false);
  }
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  void save('link');
});
savePage.addEventListener('click', () => void save('page'));
$<HTMLButtonElement>('replace').addEventListener('click', () => void answerReplace('replace'));
$<HTMLButtonElement>('keep').addEventListener('click', () => void answerReplace('keep'));
tagsInput.addEventListener('input', suggestTags);

void platform.warmUp();
const tab = await activeTab();
$<HTMLParagraphElement>('tab-title').textContent = tab?.title ?? tab?.url ?? '';
$<HTMLParagraphElement>('tab-url').textContent = tab?.url ?? '';
if (tab?.url && /^https?:/i.test(tab.url)) {
  setBusy(false);
  const [tags, status] = await Promise.all([platform.tags(), platform.status(tab.url)]);
  knownTags = tags;
  suggestTags();
  if (status.saved) setStatus(status.kind === 'page' ? 'This page is saved.' : 'This link is saved.');
} else {
  setStatus('Only web pages can be saved.');
}
