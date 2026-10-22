// Frontmatter handling for Satchel Markdown files (spec §5). The renderer only needs to find and strip the YAML block;
// the Item's fields already come from the model, so the YAML itself is returned unparsed (no YAML parser shipped).

export interface FrontmatterSplit {
  /** The YAML between the fences, without them. `null` when the file has no (closed) frontmatter block. */
  frontmatter: string | null;
  /** Everything after the closing fence. */
  body: string;
}

// The opening fence must be the very first line; the closing fence is `---` (or YAML's `...`) on its own line.
const OPEN = /^---[ \t]*\r?\n/;
const CLOSE = /^(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/m;

/** Splits a leading `---` YAML block from the Markdown body. Without a closing fence, nothing is treated as frontmatter. */
export function splitFrontmatter(markdown: string): FrontmatterSplit {
  const text = markdown.charCodeAt(0) === 0xfeff ? markdown.slice(1) : markdown;
  const open = OPEN.exec(text);
  if (!open) return { frontmatter: null, body: text };
  const rest = text.slice(open[0].length);
  const close = CLOSE.exec(rest);
  if (!close) return { frontmatter: null, body: text };
  const yaml = rest.slice(0, close.index).replace(/\r?\n$/, '');
  return { frontmatter: yaml, body: rest.slice(close.index + close[0].length) };
}
