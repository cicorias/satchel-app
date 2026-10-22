// URL normalization v1 and deterministic item IDs (spec §7.2). Changing any rule here changes IDs, which
// needs a migration, so bump NORMALIZATION_VERSION and keep the old behavior reachable.

import { sha256 } from '@noble/hashes/sha2.js';
import { bytesToHex, utf8ToBytes } from '@noble/hashes/utils.js';
import { getDomain } from 'tldts';
import type { ItemId } from './item.ts';

export const NORMALIZATION_VERSION = 1 as const;

export class UnsupportedUrlError extends Error {
  constructor(readonly url: string) {
    super(`only http and https URLs can be saved: ${url}`);
    this.name = 'UnsupportedUrlError';
  }
}

const TRACKING_PARAMS = new Set([
  'fbclid',
  'gclid',
  'dclid',
  'msclkid',
  'mc_cid',
  'mc_eid',
  'igshid',
  'ref_src',
  '_hsenc',
  '_hsmi',
  'yclid',
]);

const isTrackingParam = (key: string) => {
  const k = key.toLowerCase();
  return k.startsWith('utm_') || TRACKING_PARAMS.has(k);
};

function parseHttpUrl(input: string): URL {
  let url: URL;
  try {
    url = new URL(input.trim());
  } catch {
    throw new UnsupportedUrlError(input);
  }
  if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new UnsupportedUrlError(input);
  return url;
}

function decodeKey(raw: string): string {
  try {
    return decodeURIComponent(raw.replace(/\+/g, ' '));
  } catch {
    return raw;
  }
}

/**
 * Steps 1–6 of §7.2 for a single URL. The query string keeps its original encoding: parameters are
 * filtered and reordered as raw `key=value` segments, never re-serialized.
 */
export function normalizeUrl(input: string): string {
  const url = parseHttpUrl(input);
  // WHATWG URL parsing already lowercases the scheme and host and drops default ports.
  const host = url.hostname.startsWith('www.') ? url.hostname.slice(4) : url.hostname;
  const port = url.port ? `:${url.port}` : '';

  const segments = url.search
    .slice(1)
    .split('&')
    .filter((segment) => segment !== '')
    .map((segment) => ({ segment, key: decodeKey(segment.split('=', 1)[0] ?? '') }))
    .filter(({ key }) => !isTrackingParam(key));
  // Array.prototype.sort is stable, so repeated keys keep their relative order.
  segments.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0));
  const query = segments.length > 0 ? `?${segments.map(({ segment }) => segment).join('&')}` : '';

  const path = url.pathname !== '/' && url.pathname.endsWith('/') ? url.pathname.slice(0, -1) : url.pathname;
  const fragment = url.hash.startsWith('#!') ? url.hash : '';

  return `${url.protocol}//${host}${port}${path}${query}${fragment}`;
}

/**
 * The registrable domain ("eTLD+1"), using the Public Suffix List including its private section,
 * so `alice.github.io` and `bob.github.io` are different sites. IPs and single-label hosts have none.
 */
function registrableDomain(url: URL): string | null {
  return getDomain(url.hostname, { allowPrivateDomains: true });
}

/**
 * Step 7 of §7.2: the canonical URL is the identity input only when it is an http(s) URL on the same
 * registrable domain as the page URL (hosts without one must match exactly). Otherwise the page URL is.
 */
export function identityUrl(pageUrl: string, canonicalUrl?: string): string {
  const page = parseHttpUrl(pageUrl);
  if (!canonicalUrl) return pageUrl;
  let canonical: URL;
  try {
    canonical = parseHttpUrl(new URL(canonicalUrl, page).href);
  } catch {
    return pageUrl;
  }
  const pageSite = registrableDomain(page);
  const canonicalSite = registrableDomain(canonical);
  const sameSite = pageSite !== null ? pageSite === canonicalSite : page.hostname === canonical.hostname;
  return sameSite ? canonical.href : pageUrl;
}

/** The full §7.2 algorithm: pick the identity URL, then normalize it. */
export function normalizedUrlFor(pageUrl: string, canonicalUrl?: string): string {
  return normalizeUrl(identityUrl(pageUrl, canonicalUrl));
}

/** `"u_"` + the first 32 hex characters of SHA-256 over the UTF-8 bytes of the normalized URL. */
export function itemIdFor(normalizedUrl: string): ItemId {
  return `u_${bytesToHex(sha256(utf8ToBytes(normalizedUrl))).slice(0, 32)}`;
}
