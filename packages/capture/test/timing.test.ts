// Informational timing over the golden fixtures (spec §14 Phase 1): captureLink should be well under 50 ms and
// capturePage under 1.5 s per page. It never fails. Runs only via `mise run report:capture-timing`.

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { parseHTML } from 'linkedom';
import { test } from 'vitest';
import { captureLink, capturePage } from '../src/index.ts';

const root = new URL('../../../fixtures/pages/', import.meta.url);
const ROUNDS = 5;
const BUDGET = { link: 50, page: 1500 };

const median = (values: number[]) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)] ?? 0;

test.runIf(process.env.CAPTURE_TIMING === '1')('capture timing over the fixture set', async () => {
  const names = readdirSync(root).filter((name) => existsSync(new URL(`${name}/input.html`, root)));
  const rows: { name: string; kb: number; link: number; page: number }[] = [];
  for (const name of names.sort()) {
    const html = readFileSync(new URL(`${name}/input.html`, root), 'utf8');
    const pageUrl = readFileSync(new URL(`${name}/url.txt`, root), 'utf8').trim();
    const link: number[] = [];
    const page: number[] = [];
    // Parsing isn't timed: in production the browser has already built the DOM.
    for (let round = 0; round <= ROUNDS; round++) {
      const doc = parseHTML(html).document as unknown as Document;
      let started = performance.now();
      captureLink(doc, { pageUrl });
      const linkMs = performance.now() - started;
      started = performance.now();
      await capturePage(doc, { pageUrl });
      const pageMs = performance.now() - started;
      // Round 0 warms up the JIT and is discarded.
      if (round > 0) {
        link.push(linkMs);
        page.push(pageMs);
      }
    }
    rows.push({ name, kb: html.length / 1024, link: median(link), page: median(page) });
  }

  const flag = (ms: number, budget: number) => (ms <= budget ? ' ' : '!');
  const lines = rows.map(
    (r) =>
      `${r.name.padEnd(34)} ${r.kb.toFixed(1).padStart(6)} KB  link ${r.link.toFixed(2).padStart(7)} ms${flag(r.link, BUDGET.link)}  page ${r.page.toFixed(1).padStart(7)} ms${flag(r.page, BUDGET.page)}`,
  );
  const worst = (key: 'link' | 'page') => Math.max(...rows.map((r) => r[key]));
  console.log(
    [
      `Capture timing: median of ${ROUNDS} runs, linkedom on Node ${process.version}. "!" marks a page over budget (link ${BUDGET.link} ms, page ${BUDGET.page} ms).`,
      ...lines,
      `max: link ${worst('link').toFixed(2)} ms, page ${worst('page').toFixed(1)} ms over ${rows.length} fixtures`,
    ].join('\n'),
  );
});
