// App Store screenshot frames (6.9-inch iPhone, 1320×2868): a headline, a subline, and a rounded drop zone 1080 px
// wide. `render.mjs` draws them empty; `screenshots.mjs` draws them around real simulator captures.
import { palette, svg } from '../../art/src/satchel.mjs';

export const FONT = "'Avenir Next', 'Helvetica Neue', Helvetica, Arial, sans-serif";

/** In order: the capture each frame holds is `apple/build/screenshots/<capture>.png` (StoreScreenshotTests). */
export const FRAMES = [
  { headline: 'Save any page in one tap', sub: 'From Safari or the share sheet', capture: '1-share' },
  { headline: 'Clean Markdown you own', sub: 'Readable anywhere, with frontmatter', capture: '2-page' },
  { headline: 'Your iCloud, your library', sub: 'No accounts, no servers, no tracking', capture: '3-library' },
];

const W = 1320;
const H = 2868;
const ZONE = { x: 120, y: 520, w: 1080, h: 2348, r: 120 };

/** The frame; with `captureBase64` (a PNG), the capture fills the drop zone, clipped to its rounded corners. */
export function screenshotFrame(headline, sub, captureBase64) {
  const zone = captureBase64
    ? `<clipPath id="zone"><rect x="${ZONE.x}" y="${ZONE.y}" width="${ZONE.w}" height="${ZONE.h}" rx="${ZONE.r}"/></clipPath>
  <image href="data:image/png;base64,${captureBase64}" x="${ZONE.x}" y="${ZONE.y}" width="${ZONE.w}" height="${ZONE.h}"
    preserveAspectRatio="xMidYMin slice" clip-path="url(#zone)"/>
  <rect x="${ZONE.x}" y="${ZONE.y}" width="${ZONE.w}" height="${ZONE.h}" rx="${ZONE.r}" fill="none" stroke="${palette.leatherDark}" stroke-width="6"/>`
    : `<!-- Screenshot drop zone: composite a 6.9" capture scaled to 1080 wide here (mise run art:screenshots). -->
  <rect x="${ZONE.x}" y="${ZONE.y}" width="${ZONE.w}" height="${ZONE.h}" rx="${ZONE.r}" fill="${palette.ink}" opacity="0.55"/>
  <rect x="${ZONE.x}" y="${ZONE.y}" width="${ZONE.w}" height="${ZONE.h}" rx="${ZONE.r}" fill="none" stroke="${palette.leatherDark}" stroke-width="6" stroke-dasharray="28 20"/>`;
  return svg(
    W,
    H,
    `
  <defs><linearGradient id="f" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${palette.cedarTop}"/><stop offset="1" stop-color="${palette.cedarBottom}"/>
  </linearGradient></defs>
  <rect width="${W}" height="${H}" fill="url(#f)"/>
  <text x="${W / 2}" y="300" text-anchor="middle" font-family="${FONT}" font-weight="700" font-size="104" fill="${palette.cream}">${headline}</text>
  <text x="${W / 2}" y="400" text-anchor="middle" font-family="${FONT}" font-weight="500" font-size="52" fill="${palette.brass}">${sub}</text>
  ${zone}`,
  );
}
