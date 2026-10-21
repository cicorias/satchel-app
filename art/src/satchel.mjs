// Design source for all Satchel artwork: a leather satchel whose strap is a bookmark ribbon.
// Everything is drawn on a 1024×1024 grid; scripts/art/render.mjs composes and rasterizes it.

export const palette = {
  cedarTop: '#5e3b22',
  cedarBottom: '#3a2313',
  leatherLight: '#d6a066',
  leatherDark: '#b97d43',
  flap: '#a5672f',
  flapShade: '#8f5726',
  handle: '#a36a36',
  stitch: '#f4e8d2',
  cream: '#f4e8d2',
  ribbon: '#2e6b4e',
  ribbonEdge: '#245a41',
  brass: '#e6c07a',
  brassEdge: '#8a5a2e',
  ink: '#2a1a0e',
};

// Grayscale stand-ins for the iOS "tinted" appearance: the system supplies the hue.
export const tintedPalette = {
  ...palette,
  leatherLight: '#c9c9c9',
  leatherDark: '#b0b0b0',
  flap: '#8e8e8e',
  flapShade: '#7a7a7a',
  handle: '#6a6a6a',
  stitch: '#e6e6e6',
  ribbon: '#ffffff',
  ribbonEdge: '#dcdcdc',
  brass: '#f2f2f2',
  brassEdge: '#5a5a5a',
};

/**
 * The bag itself, centered on the 1024 grid, no background.
 * @param {object} o
 * @param {typeof palette} [o.p] colors
 * @param {boolean} [o.detail] stitching and shading (off for ≤32 px)
 * @param {string} [o.id] gradient id prefix, unique per document
 */
export function bag({ p = palette, detail = true, id = 'b' } = {}) {
  const handleWidth = detail ? 48 : 64;
  return `
  <defs>
    <linearGradient id="${id}-body" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${p.leatherLight}"/>
      <stop offset="1" stop-color="${p.leatherDark}"/>
    </linearGradient>
    <linearGradient id="${id}-flap" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${p.flap}"/>
      <stop offset="1" stop-color="${p.flapShade}"/>
    </linearGradient>
  </defs>
  <path d="M396 360 V300 A116 116 0 0 1 628 300 V360" fill="none" stroke="${p.handle}" stroke-width="${handleWidth}" stroke-linecap="round"/>
  <rect x="196" y="336" width="632" height="452" rx="84" fill="url(#${id}-body)"/>
  ${detail ? `<clipPath id="${id}-clip"><rect x="196" y="336" width="632" height="452" rx="84"/></clipPath><rect x="196" y="716" width="632" height="72" fill="${p.flapShade}" opacity="0.18" clip-path="url(#${id}-clip)"/>` : ''}
  <path d="M280 336 H744 A84 84 0 0 1 828 420 V566 Q828 600 794 600 H230 Q196 600 196 566 V420 A84 84 0 0 1 280 336 Z" fill="url(#${id}-flap)"/>
  ${
    detail
      ? `<path d="M292 366 H732 A56 56 0 0 1 788 422 V562 H236 V422 A56 56 0 0 1 292 366 Z" fill="none" stroke="${p.stitch}" stroke-opacity="0.55" stroke-width="8" stroke-dasharray="22 16" stroke-linecap="round"/>`
      : ''
  }
  <path d="M460 336 H564 V742 L512 694 L460 742 Z" fill="${p.ribbon}"/>
  ${detail ? `<path d="M552 336 H564 V742 L552 731 Z" fill="${p.ribbonEdge}"/>` : ''}
  <rect x="478" y="572" width="68" height="56" rx="14" fill="${p.brass}" stroke="${p.brassEdge}" stroke-width="${detail ? 8 : 12}"/>
  ${detail ? `<rect x="500" y="590" width="24" height="20" rx="5" fill="${p.brassEdge}" opacity="0.6"/>` : ''}`;
}

/** Full-bleed cedar background (iOS masks the corners itself). */
export function background({ p = palette, id = 'bg' } = {}) {
  return `
  <defs>
    <linearGradient id="${id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${p.cedarTop}"/>
      <stop offset="1" stop-color="${p.cedarBottom}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" fill="url(#${id})"/>`;
}

/** Rounded-square badge for browser toolbars and stores, where nothing masks the icon. */
export function badge({ detail = true, id = 'g' } = {}) {
  return `
  <defs>
    <linearGradient id="${id}-bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${palette.cedarTop}"/>
      <stop offset="1" stop-color="${palette.cedarBottom}"/>
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="1024" height="1024" rx="228" fill="url(#${id}-bg)"/>
  <g transform="translate(512 548) scale(${detail ? 1.08 : 1.18}) translate(-512 -548)">${bag({ detail, id })}</g>`;
}

export const svg = (w, h, body, viewBox = `0 0 ${w} ${h}`) =>
  `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${viewBox}">${body}\n</svg>\n`;
