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
