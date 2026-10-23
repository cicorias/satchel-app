// Renders every icon and store asset from art/src/satchel.mjs.
// Writes SVG masters to art/svg/ and PNGs to the places each platform expects.
// Outputs are committed (they rarely change); re-run with `mise run art` after editing the design.
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Resvg } from '@resvg/resvg-js';
import { background, badge, bag, palette, svg, tintedPalette } from '../../art/src/satchel.mjs';
import { FONT, FRAMES, screenshotFrame } from './frames.mjs';

const root = join(import.meta.dirname, '../..');

const TAGLINE = 'Save the web as Markdown, into your own iCloud.';

function write(rel, data) {
  const path = join(root, rel);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, data);
}

function png(svgText, width, rel) {
  const out = new Resvg(svgText, {
    fitTo: { mode: 'width', value: width },
    font: { loadSystemFonts: true, defaultFontFamily: 'Helvetica Neue' },
  })
    .render()
    .asPng();
  write(rel, out);
  console.log(`  ${rel} (${width}px)`);
}

// --- masters ------------------------------------------------------------------
const masters = {
  'app-icon': svg(1024, 1024, background() + bag()),
  'app-icon-dark': svg(1024, 1024, bag({ id: 'd' })),
  'app-icon-tinted': svg(1024, 1024, bag({ p: tintedPalette, id: 't' })),
  badge: svg(1024, 1024, badge()),
  'badge-small': svg(1024, 1024, badge({ detail: false })),
  // Separate layers for Icon Composer (.icon, Liquid Glass): import these three in order.
  'layers/1-background': svg(1024, 1024, background()),
  'layers/2-bag': svg(1024, 1024, bag()),
};
console.log('masters');
for (const [name, text] of Object.entries(masters)) {
  write(`art/svg/${name}.svg`, text);
  console.log(`  art/svg/${name}.svg`);
}

// --- iOS app icon (asset catalog: any / dark / tinted) -----------------------
console.log('ios');
const appiconset = 'apple/Satchel/Resources/Assets.xcassets/AppIcon.appiconset';
png(masters['app-icon'], 1024, `${appiconset}/icon-1024.png`);
png(masters['app-icon-dark'], 1024, `${appiconset}/icon-1024-dark.png`);
png(masters['app-icon-tinted'], 1024, `${appiconset}/icon-1024-tinted.png`);
write(
  `${appiconset}/Contents.json`,
  `${JSON.stringify(
    {
      images: [
        { filename: 'icon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' },
        {
          appearances: [{ appearance: 'luminosity', value: 'dark' }],
          filename: 'icon-1024-dark.png',
          idiom: 'universal',
          platform: 'ios',
          size: '1024x1024',
        },
        {
          appearances: [{ appearance: 'luminosity', value: 'tinted' }],
          filename: 'icon-1024-tinted.png',
          idiom: 'universal',
          platform: 'ios',
          size: '1024x1024',
        },
      ],
      info: { author: 'xcode', version: 1 },
    },
    null,
    2,
  )}\n`,
);

// --- browser extension (WXT picks up public/icon/<size>.png) -----------------
console.log('extension');
for (const size of [16, 32]) png(masters['badge-small'], size, `apps/extension/public/icon/${size}.png`);
for (const size of [48, 96, 128]) png(masters.badge, size, `apps/extension/public/icon/${size}.png`);

// --- store artwork -------------------------------------------------------------
function promo(w, h) {
  const s = h / 560; // layouts are drawn for a 1400×560 marquee and scaled
  const icon = 360 * s;
  const titleSize = 132 * s;
  const tagSize = 34 * s;
  const x = 120 * s;
  return svg(
    w,
    h,
    `
  <defs><linearGradient id="p" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="${palette.cedarTop}"/><stop offset="1" stop-color="${palette.cedarBottom}"/>
  </linearGradient></defs>
  <rect width="${w}" height="${h}" fill="url(#p)"/>
  <g transform="translate(${x} ${(h - icon) / 2}) scale(${icon / 1024})">${bag({ id: 'pb' })}</g>
  <text x="${x + icon + 60 * s}" y="${h / 2 + 10 * s}" font-family="${FONT}" font-weight="700" font-size="${titleSize}" fill="${palette.cream}">Satchel</text>
  <text x="${x + icon + 64 * s}" y="${h / 2 + 80 * s}" font-family="${FONT}" font-weight="500" font-size="${tagSize}" fill="${palette.brass}">${TAGLINE}</text>`,
  );
}

function smallPromo(w, h) {
  const icon = h * 0.62;
  return svg(
    w,
    h,
    `
  <defs><linearGradient id="p" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="${palette.cedarTop}"/><stop offset="1" stop-color="${palette.cedarBottom}"/>
  </linearGradient></defs>
  <rect width="${w}" height="${h}" fill="url(#p)"/>
  <g transform="translate(${(w - icon) / 2} ${h * 0.06}) scale(${icon / 1024})">${bag({ id: 'sb' })}</g>
  <text x="${w / 2}" y="${h * 0.8}" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="${h * 0.15}" fill="${palette.cream}">Satchel</text>
  <text x="${w / 2}" y="${h * 0.92}" text-anchor="middle" font-family="${FONT}" font-weight="500" font-size="${h * 0.06}" fill="${palette.brass}">Links and pages, saved as Markdown</text>`,
  );
}

console.log('stores');
png(
  svg(1024, 1024, `<g transform="translate(128 128) scale(0.75)">${badge({ id: 'c' })}</g>`),
  128,
  'store/chrome/icon-128.png',
);
png(smallPromo(440, 280), 440, 'store/chrome/promo-small-440x280.png');
png(promo(1400, 560), 1400, 'store/chrome/promo-marquee-1400x560.png');
png(masters.badge, 300, 'store/edge/logo-300.png');
png(smallPromo(440, 280), 440, 'store/edge/promo-small-440x280.png');
png(promo(1400, 560), 1400, 'store/edge/promo-large-1400x560.png');
FRAMES.forEach(({ headline, sub }, i) => {
  png(screenshotFrame(headline, sub), 1320, `store/app-store/frame-${i + 1}-1320x2868.png`);
});
png(promo(1280, 640), 1280, 'store/github/social-preview-1280x640.png');

// --- site (GitHub Pages) -------------------------------------------------------
console.log('site');
png(masters['badge-small'], 32, 'site/assets/favicon-32.png');
png(masters['app-icon'], 180, 'site/assets/apple-touch-icon.png');
png(masters.badge, 512, 'site/assets/icon-512.png');
png(promo(1200, 630), 1200, 'site/assets/og.png');
