// Composites the simulator captures from StoreScreenshotTests into the App Store frames:
// apple/build/screenshots/<capture>.png → store/app-store/screenshot-<n>-1320x2868.png. Run by screenshots.sh.
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { Resvg } from '@resvg/resvg-js';
import { FRAMES, screenshotFrame } from './frames.mjs';

const root = join(import.meta.dirname, '../..');
const captures = process.env.CAPTURES ?? join(root, 'apple/build/screenshots');

let missing = 0;
FRAMES.forEach(({ headline, sub, capture }, i) => {
  const source = join(captures, `${capture}.png`);
  if (!existsSync(source)) {
    console.error(`missing ${source}`);
    missing += 1;
    return;
  }
  const svgText = screenshotFrame(headline, sub, readFileSync(source).toString('base64'));
  const out = new Resvg(svgText, {
    fitTo: { mode: 'width', value: 1320 },
    font: { loadSystemFonts: true, defaultFontFamily: 'Helvetica Neue' },
  })
    .render()
    .asPng();
  const rel = `store/app-store/screenshot-${i + 1}-1320x2868.png`;
  writeFileSync(join(root, rel), out);
  console.log(`  ${rel}`);
});
process.exit(missing ? 1 : 0);
