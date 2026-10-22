// Item and ImageRef (spec §7.1). Mirrored by SatchelKit in Swift; schema/item.schema.json is the
// JSON contract both sides test against, using the shared fixtures in fixtures/model/.
// Objects may carry fields this version doesn't know about. They must survive a decode/encode round trip.

export const SCHEMA_VERSION = 1 as const;

/** "u_" + the first 32 hex chars of SHA-256(normalizedUrl) (§7.2). */
export type ItemId = string;

export type ClientId = 'chrome' | 'edge' | 'safari-ios' | 'safari-macos' | 'ios-share' | 'ios-app' | 'macos-app';

export const CLIENT_IDS = [
  'chrome',
  'edge',
  'safari-ios',
  'safari-macos',
  'ios-share',
  'ios-app',
  'macos-app',
] as const satisfies readonly ClientId[];

export type ItemKind = 'link' | 'page';

/** `pending` means the item is waiting for metadata enrichment. */
export type MetadataStatus = 'complete' | 'pending' | 'failed';

/** Only `remote` exists until Phase 5 stores images. */
export type ImageStatus = 'remote' | 'stored' | 'failed';

export interface ImageRef {
  originalUrl: string;
  alt?: string;
  status: ImageStatus;
  /** Provider-specific reference once the image is stored. */
  assetKey?: string;
  contentType?: string;
  bytes?: number;
}

export interface ItemSource {
  client: ClientId;
  version: string;
}

export interface PageInfo {
  wordCount: number;
  readingMinutes: number;
  engine: string;
  images: ImageRef[];
}

export interface Item {
  schemaVersion: typeof SCHEMA_VERSION;
  id: ItemId;
  kind: ItemKind;
  /** As captured. */
  url: string;
  canonicalUrl: string;
  /** §7.2; the input to `id`. */
  normalizedUrl: string;
  title: string;
  description?: string;
  siteName?: string;
  author?: string;
  /** ISO 8601. */
  publishedAt?: string;
  imageUrl?: string;
  faviconUrl?: string;
  lang?: string;
  /** Lowercase, trimmed, deduplicated. */
  tags: string[];
  note?: string;
  /** The capture was a selection, not the whole page (FR-10). */
  selection?: boolean;
  /** First save; never changes. */
  createdAt: string;
  updatedAt: string;
  /** Last page capture. */
  capturedAt?: string;
  metadataStatus: MetadataStatus;
  source: ItemSource;
  page?: PageInfo;
}

// Every property of each type, with `true` for required and `false` for optional. The compiler checks each
// map against its type both ways, so the schema test catches a property or `required` entry that drifted.
type Shape<T> = { [K in keyof T]-?: object extends Pick<T, K> ? false : true };

export const ITEM_SHAPE = {
  schemaVersion: true,
  id: true,
  kind: true,
  url: true,
  canonicalUrl: true,
  normalizedUrl: true,
  title: true,
  description: false,
  siteName: false,
  author: false,
  publishedAt: false,
  imageUrl: false,
  faviconUrl: false,
  lang: false,
  tags: true,
  note: false,
  selection: false,
  createdAt: true,
  updatedAt: true,
  capturedAt: false,
  metadataStatus: true,
  source: true,
  page: false,
} as const satisfies Shape<Item>;

export const ITEM_SOURCE_SHAPE = { client: true, version: true } as const satisfies Shape<ItemSource>;

export const PAGE_INFO_SHAPE = {
  wordCount: true,
  readingMinutes: true,
  engine: true,
  images: true,
} as const satisfies Shape<PageInfo>;

export const IMAGE_REF_SHAPE = {
  originalUrl: true,
  alt: false,
  status: true,
  assetKey: false,
  contentType: false,
  bytes: false,
} as const satisfies Shape<ImageRef>;
