// JSON-LD reading for the metadata resolver (spec §4.2, "JSON-LD rules").

export type JsonLdNode = Record<string, unknown>;

/** In preference order: the first type in this list that any node has wins. */
export const PREFERRED_TYPES = [
  'Article',
  'NewsArticle',
  'BlogPosting',
  'TechArticle',
  'WebPage',
  'VideoObject',
  'Product',
  'Recipe',
] as const;

const isNode = (value: unknown): value is JsonLdNode =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Flatten top-level arrays and `@graph` containers (nested ones too) into a list of nodes. */
function flatten(value: unknown, out: JsonLdNode[]): void {
  if (Array.isArray(value)) {
    for (const entry of value) flatten(entry, out);
  } else if (isNode(value)) {
    if ('@graph' in value) flatten(value['@graph'], out);
    if ('@type' in value || !('@graph' in value)) out.push(value);
  }
}

export interface JsonLd {
  nodes: JsonLdNode[];
  /** Follow `{"@id": …}` references to the node that defines that `@id`, if any. */
  resolve(value: unknown): unknown;
  /** The node metadata should come from (see `PREFERRED_TYPES`), if any. */
  primary: JsonLdNode | undefined;
}

/** `schema:Article` and `https://schema.org/Article` both mean `Article`. */
export function typesOf(node: JsonLdNode): string[] {
  const raw = node['@type'];
  const list = Array.isArray(raw) ? raw : [raw];
  return list
    .filter((t): t is string => typeof t === 'string')
    .map((t) => t.replace(/^(?:https?:\/\/schema\.org\/|schema:)/, ''));
}

export function readJsonLd(doc: Document, warnings: string[]): JsonLd {
  const nodes: JsonLdNode[] = [];
  for (const script of doc.querySelectorAll('script[type="application/ld+json" i]')) {
    try {
      flatten(JSON.parse(script.textContent ?? ''), nodes);
    } catch {
      warnings.push('invalid-json-ld');
    }
  }

  const byId = new Map<string, JsonLdNode>();
  for (const node of nodes) {
    const id = node['@id'];
    if (typeof id === 'string' && Object.keys(node).some((key) => key !== '@id')) byId.set(id, node);
  }
  const resolve = (value: unknown): unknown => {
    if (isNode(value) && typeof value['@id'] === 'string' && Object.keys(value).length === 1) {
      return byId.get(value['@id']) ?? value;
    }
    return value;
  };

  let primary: JsonLdNode | undefined;
  let bestRank = Number.POSITIVE_INFINITY;
  for (const node of nodes) {
    for (const type of typesOf(node)) {
      const rank = (PREFERRED_TYPES as readonly string[]).indexOf(type);
      if (rank !== -1 && rank < bestRank) {
        bestRank = rank;
        primary = node;
      }
    }
  }
  primary ??= nodes.find((node) => typeof node.name === 'string' || typeof node.headline === 'string');

  return { nodes, resolve, primary };
}
