// Merge rules (spec §7.3), used both when an existing ID is saved again and when resolving sync conflicts.
// `mergeItems` is pure and commutative: two devices that merge the same pair in either order converge.

import type { Item, MetadataStatus } from './item.ts';

export interface MergeResult {
  item: Item;
  /** Whose Markdown body the merged item keeps. `none` means neither side is a page capture. */
  body: 'a' | 'b' | 'none';
  /**
   * Both sides carry a page body and one replaces the other. On an interactive re-save the client asks
   * "Replace saved copy?" first (§7.3). Sync conflict resolution applies the merge without asking.
   */
  replacesBody: boolean;
}

/** Metadata fields: the newer capture's value wins, but a non-empty value is never replaced by an empty one. */
const METADATA_FIELDS = [
  'url',
  'canonicalUrl',
  'title',
  'description',
  'siteName',
  'author',
  'publishedAt',
  'imageUrl',
  'faviconUrl',
  'lang',
] as const satisfies readonly (keyof Item)[];

const STATUS_RANK: Record<MetadataStatus, number> = { complete: 2, pending: 1, failed: 0 };

const isEmpty = (value: unknown) => value === undefined || (typeof value === 'string' && value.trim() === '');

/** ISO 8601 timestamps from the model compare correctly as strings only when normalized, so compare instants. */
const time = (iso: string | undefined) => (iso === undefined ? Number.NEGATIVE_INFINITY : Date.parse(iso));

/**
 * A total order on items. Ties on the given timestamp fall back to `updatedAt` and then to the serialized
 * item, so the result never depends on argument order.
 */
function compareBy(a: Item, b: Item, at: (item: Item) => string | undefined): number {
  return (
    Math.sign(time(at(a)) - time(at(b))) ||
    Math.sign(time(a.updatedAt) - time(b.updatedAt)) ||
    (JSON.stringify(a) < JSON.stringify(b) ? -1 : JSON.stringify(a) > JSON.stringify(b) ? 1 : 0)
  );
}

/** A page capture's time is `capturedAt`; a link save's is when it was last updated. */
const captureTime = (item: Item) => item.capturedAt ?? item.updatedAt;

export function mergeItems(a: Item, b: Item): MergeResult {
  if (a.id !== b.id) throw new Error(`cannot merge different items: ${a.id} and ${b.id}`);

  const [olderCapture, newerCapture] = compareBy(a, b, captureTime) <= 0 ? [a, b] : [b, a];
  const [olderUpdate, newerUpdate] = compareBy(a, b, (item) => item.updatedAt) <= 0 ? [a, b] : [b, a];

  // Unknown fields from newer clients survive; on a clash the newer capture's value wins.
  const merged: Item = { ...olderCapture, ...newerCapture };

  for (const field of METADATA_FIELDS) {
    const value = isEmpty(newerCapture[field]) ? olderCapture[field] : newerCapture[field];
    if (value === undefined) delete merged[field];
    else (merged as unknown as Record<string, unknown>)[field] = value;
  }

  merged.createdAt = time(a.createdAt) <= time(b.createdAt) ? a.createdAt : b.createdAt;
  merged.updatedAt = newerUpdate.updatedAt;
  merged.kind = a.kind === 'page' || b.kind === 'page' ? 'page' : 'link';
  // Union in a stable order: the older side's tags as the user ordered them, then any new ones.
  merged.tags = [...new Set([...olderUpdate.tags, ...newerUpdate.tags])];
  merged.metadataStatus =
    STATUS_RANK[a.metadataStatus] >= STATUS_RANK[b.metadataStatus] ? a.metadataStatus : b.metadataStatus;
  merged.source = newerCapture.source;

  // Note: the most recently updated side wins. An absent note means "this client didn't set one", so it
  // never clears the other side's note; an empty string is an explicit clear and does.
  const note = newerUpdate.note ?? olderUpdate.note;
  if (note === undefined) delete merged.note;
  else merged.note = note;

  // Body: the newer page capture wins, and `page`, `selection`, and `capturedAt` travel with it.
  const pages = [a, b].filter((item) => item.kind === 'page');
  const bodyOwner = pages.length === 2 ? newerCapture : pages.length === 1 ? pages[0] : undefined;
  delete merged.page;
  delete merged.selection;
  delete merged.capturedAt;
  if (bodyOwner) {
    if (bodyOwner.page !== undefined) merged.page = bodyOwner.page;
    if (bodyOwner.selection !== undefined) merged.selection = bodyOwner.selection;
    if (bodyOwner.capturedAt !== undefined) merged.capturedAt = bodyOwner.capturedAt;
  }

  return {
    item: merged,
    body: bodyOwner === undefined ? 'none' : bodyOwner === a ? 'a' : 'b',
    replacesBody: pages.length === 2,
  };
}
