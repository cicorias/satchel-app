import type { Item } from './item.ts';

// YAML frontmatter for saved Markdown (spec §5). Free text is always double-quoted; other values stay plain
// only when YAML would read them back as the same string.

export interface Frontmatter {
  id: string;
  type: 'link' | 'page';
  title: string;
  url: string;
  canonical: string;
  site?: string;
  author?: string;
  published?: string;
  saved: string;
  updated: string;
  description?: string;
  image?: string;
  tags: string[];
  source?: string;
  engine?: string;
}

const ORDER: (keyof Frontmatter)[] = [
  'id',
  'type',
  'title',
  'url',
  'canonical',
  'site',
  'author',
  'published',
  'saved',
  'updated',
  'description',
  'image',
  'tags',
  'source',
  'engine',
];
const ALWAYS_QUOTED = new Set<keyof Frontmatter>(['title', 'description', 'author', 'site']);

// YAML 1.1 and 1.2 words that would load as booleans or null.
const RESERVED = /^(?:true|false|yes|no|on|off|y|n|null|~)$/i;

/** A double-quoted YAML scalar. JSON string syntax is valid YAML. */
// JSON leaves U+2028/U+2029 raw, but YAML 1.1 reads them as line breaks.
const quoted = (value: string) =>
  JSON.stringify(value)
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');

/** Plain when unambiguous: no indicator first, no ": " or " #", no edge spaces, not reserved or a number. */
export function yamlScalar(value: string): string {
  const plain =
    value !== '' &&
    !/^[-?:,[\]{}#&*!|>'"%@`\s]/.test(value) &&
    !/\s$/.test(value) &&
    // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters must force quoting
    !/: |:$| #|[\u0000-\u001f\u007f\u2028\u2029]/.test(value) &&
    !RESERVED.test(value) &&
    !/^[-+]?(?:\.?\d|\.(?:inf|nan))/i.test(value);
  return plain ? value : quoted(value);
}

export function formatFrontmatter(fields: Frontmatter): string {
  const lines = ['---'];
  for (const key of ORDER) {
    const value = fields[key];
    if (value === undefined) continue;
    if (Array.isArray(value)) lines.push(`${key}: [${value.map(yamlScalar).join(', ')}]`);
    else if (key === 'saved' || key === 'updated' || key === 'published') lines.push(`${key}: ${value}`);
    else lines.push(`${key}: ${ALWAYS_QUOTED.has(key) ? quoted(value) : yamlScalar(value)}`);
  }
  lines.push('---');
  return `${lines.join('\n')}\n`;
}

/** The frontmatter for an Item, from its current fields (spec §5), so an export is never stale. */
export function frontmatterFor(item: Item): Frontmatter {
  const fields: Frontmatter = {
    id: item.id,
    type: item.kind,
    title: item.title,
    url: item.url,
    canonical: item.canonicalUrl,
    saved: item.createdAt,
    updated: item.updatedAt,
    tags: item.tags,
    source: item.source.client,
  };
  const optional: Record<string, string | undefined> = {
    site: item.siteName,
    author: item.author,
    published: item.publishedAt,
    description: item.description,
    image: item.imageUrl,
    engine: item.page?.engine,
  };
  for (const [key, value] of Object.entries(optional)) {
    if (value !== undefined && value !== '') Object.assign(fields, { [key]: value });
  }
  return fields;
}

/**
 * The `.md` file for an Item (spec §5): frontmatter, then the stored body for a page. A link's body is its title as
 * a heading plus the description, so a library export is uniformly Markdown.
 */
export function markdownFile(item: Item, body?: string): string {
  const content = body ?? `# ${item.title}\n${item.description ? `\n${item.description}\n` : ''}`;
  return `${formatFrontmatter(frontmatterFor(item))}\n${content}`;
}
