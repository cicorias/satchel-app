// markdown-it configuration for Satchel Markdown (spec §4.5): CommonMark + GFM tables and strikethrough (built in),
// footnotes (markdown-it-footnote), and three small rules of our own: Obsidian callouts, GFM task lists, and `$…$` /
// `$$…$$` math kept as LaTeX source. The HTML this produces is untrusted until sanitize.ts has run over it.

import MarkdownItCtor, {
  type MarkdownIt,
  type StateBlock,
  type StateCore,
  type StateInline,
  type Token,
} from 'markdown-it';
import footnote from 'markdown-it-footnote';

export interface MarkdownOptions {
  /** Pass inline HTML through to the sanitizer (Turndown keeps some tags, e.g. `<sup>`). */
  html: boolean;
}

export function createMarkdown(opts: MarkdownOptions): MarkdownIt {
  const md = new MarkdownItCtor({ html: opts.html, linkify: true, typographer: false });
  md.use(footnote);
  md.use(callouts);
  md.use(taskLists);
  md.use(math);
  md.use(tableAlign);
  return md;
}

// ---- Callouts: `> [!type][+-] Optional title` (Obsidian syntax, as Defuddle and our Turndown rules emit it) ----

// A type alias rather than an interface, so it is assignable to Token.meta's index signature.
type CalloutMeta = {
  kind: string;
  /** Obsidian's fold marker: '' (not foldable), '-' (folded), or '+' (unfolded). */
  fold: string;
};

const CALLOUT = /^\[!([A-Za-z][\w-]*)\]([+-]?)(?:[ \t]+(.*))?$/;

function callouts(md: MarkdownIt): void {
  // Runs after block parsing and before inline parsing, so the title and body are parsed as ordinary inline Markdown.
  md.core.ruler.after('block', 'satchel_callout', (state: StateCore) => {
    const tokens = state.tokens;
    for (let i = 0; i < tokens.length; i++) {
      const open = tokens[i];
      if (open?.type !== 'blockquote_open') continue;
      const p = tokens[i + 1];
      const inline = tokens[i + 2];
      if (p?.type !== 'paragraph_open' || inline?.type !== 'inline') continue;
      const newline = inline.content.indexOf('\n');
      const firstLine = newline === -1 ? inline.content : inline.content.slice(0, newline);
      const m = CALLOUT.exec(firstLine.trim());
      if (!m) continue;
      const closeIdx = findClose(tokens, i, 'blockquote_close');
      if (closeIdx === -1) continue;

      const kind = (m[1] ?? 'note').toLowerCase();
      const fold = m[2] ?? '';
      const title = (m[3] ?? '').trim() || kind.charAt(0).toUpperCase() + kind.slice(1);
      const meta: CalloutMeta = { kind, fold };

      const calloutOpen = new state.Token('callout_open', 'div', 1);
      calloutOpen.meta = meta;
      calloutOpen.block = true;
      const titleOpen = new state.Token('callout_title_open', 'div', 1);
      titleOpen.meta = meta;
      const titleInline = new state.Token('inline', '', 0);
      titleInline.content = title;
      titleInline.children = [];
      const titleClose = new state.Token('callout_title_close', 'div', -1);
      titleClose.meta = meta;
      const contentOpen = new state.Token('callout_content_open', 'div', 1);

      const contentClose = new state.Token('callout_content_close', 'div', -1);
      const calloutClose = new state.Token('callout_close', 'div', -1);
      calloutClose.meta = meta;
      tokens.splice(closeIdx, 1, contentClose, calloutClose);

      const remainder = newline === -1 ? '' : inline.content.slice(newline + 1);
      if (remainder.trim() === '') {
        tokens.splice(i, 4, calloutOpen, titleOpen, titleInline, titleClose, contentOpen); // drop the marker paragraph
      } else {
        inline.content = remainder;
        tokens.splice(i, 1, calloutOpen, titleOpen, titleInline, titleClose, contentOpen);
      }
    }
  });

  const r = md.renderer.rules;
  const esc = md.utils.escapeHtml;
  const calloutMeta = (tokens: Token[], idx: number): CalloutMeta =>
    (tokens[idx]?.meta as CalloutMeta | undefined) ?? { kind: 'note', fold: '' };
  r.callout_open = (tokens, idx) => {
    const { kind, fold } = calloutMeta(tokens, idx);
    const tag = fold ? 'details' : 'div';
    return `<${tag} class="callout" data-callout="${esc(kind)}"${fold === '+' ? ' open' : ''}>\n`;
  };
  r.callout_close = (tokens, idx) => `</${calloutMeta(tokens, idx).fold ? 'details' : 'div'}>\n`;
  r.callout_title_open = (tokens, idx) =>
    calloutMeta(tokens, idx).fold ? '<summary class="callout-title">' : '<div class="callout-title">';
  r.callout_title_close = (tokens, idx) => (calloutMeta(tokens, idx).fold ? '</summary>\n' : '</div>\n');
  r.callout_content_open = () => '<div class="callout-content">\n';
  r.callout_content_close = () => '</div>\n';
}

function findClose(tokens: Token[], openIdx: number, closeType: string): number {
  const level = tokens[openIdx]?.level;
  for (let j = openIdx + 1; j < tokens.length; j++) {
    const t = tokens[j];
    if (t?.type === closeType && t.level === level) return j;
  }
  return -1;
}

// ---- Task lists: `- [ ] todo` / `- [x] done` (GFM) ----

const TASK = /^\[([ xX])\](?:[ \t]+|$)/;

function taskLists(md: MarkdownIt): void {
  md.core.ruler.after('block', 'satchel_task_list', (state: StateCore) => {
    const tokens = state.tokens;
    for (let i = 2; i < tokens.length; i++) {
      const inline = tokens[i];
      if (inline?.type !== 'inline' || tokens[i - 1]?.type !== 'paragraph_open') continue;
      const item = tokens[i - 2];
      if (item?.type !== 'list_item_open') continue;
      const m = TASK.exec(inline.content);
      if (!m) continue;
      inline.content = inline.content.slice(m[0].length);
      item.attrJoin('class', 'task-list-item');
      const list = findOpener(tokens, i - 2);
      list?.attrJoin('class', 'contains-task-list');
      const box = new state.Token('task_checkbox', 'input', 0);
      box.meta = { checked: m[1] !== ' ' };
      tokens.splice(i, 0, box);
      i++;
    }
  });
  md.renderer.rules.task_checkbox = (tokens, idx) => {
    const checked = (tokens[idx]?.meta as { checked?: boolean } | undefined)?.checked === true;
    return `<input class="task-list-item-checkbox" type="checkbox" disabled${checked ? ' checked' : ''}> `;
  };
}

/** The list token that owns the list item at `itemIdx`. */
function findOpener(tokens: Token[], itemIdx: number): Token | undefined {
  const level = (tokens[itemIdx]?.level ?? 0) - 1;
  for (let j = itemIdx - 1; j >= 0; j--) {
    const t = tokens[j];
    if (t && t.level === level && (t.type === 'bullet_list_open' || t.type === 'ordered_list_open')) {
      if (t.attrGet('class')?.toString().includes('contains-task-list')) return undefined; // already marked
      return t;
    }
  }
  return undefined;
}

// ---- Math: keep LaTeX source verbatim (no math engine is shipped), protected from emphasis and escape parsing ----

const DOLLAR = 0x24;
const BACKSLASH = 0x5c;

function isWhitespace(code: number | undefined): boolean {
  return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
}

function isDigit(code: number | undefined): boolean {
  return code !== undefined && code >= 0x30 && code <= 0x39;
}

function mathInline(state: StateInline, silent: boolean): boolean {
  const src = state.src;
  const start = state.pos;
  if (src.charCodeAt(start) !== DOLLAR) return false;
  const display = src.charCodeAt(start + 1) === DOLLAR;
  const delim = display ? 2 : 1;
  const contentStart = start + delim;
  // Pandoc's rule: the opening `$` is followed by a non-space; the closing `$` follows a non-space and isn't followed
  // by a digit. That keeps prices ("$5 and $10") literal.
  if (!display && isWhitespace(src.charCodeAt(contentStart))) return false;
  let pos = contentStart;
  while (pos < state.posMax) {
    const code = src.charCodeAt(pos);
    if (code === BACKSLASH) {
      pos += 2;
      continue;
    }
    if (code === DOLLAR) {
      if (display) {
        if (src.charCodeAt(pos + 1) === DOLLAR) break;
      } else if (!isWhitespace(src.charCodeAt(pos - 1)) && !isDigit(src.charCodeAt(pos + 1))) {
        break;
      }
    }
    pos++;
  }
  if (pos >= state.posMax || pos === contentStart) return false;
  if (!silent) {
    const token = state.push(display ? 'math_inline_display' : 'math_inline', 'code', 0);
    token.markup = display ? '$$' : '$';
    token.content = src.slice(contentStart, pos);
  }
  state.pos = pos + delim;
  return true;
}

function mathBlock(state: StateBlock, startLine: number, endLine: number, silent: boolean): boolean {
  let pos = (state.bMarks[startLine] ?? 0) + (state.tShift[startLine] ?? 0);
  const max = state.eMarks[startLine] ?? 0;
  if ((state.sCount[startLine] ?? 0) - state.blkIndent >= 4) return false; // indented code
  if (state.src.slice(pos, pos + 2) !== '$$') return false;
  pos += 2;
  const firstLine = state.src.slice(pos, max);
  let content: string;
  let nextLine = startLine;
  const sameLine = firstLine.trim().endsWith('$$') && firstLine.trim().length >= 2;
  if (sameLine) {
    content = firstLine.trim().slice(0, -2);
  } else {
    const lines: string[] = [];
    if (firstLine.trim()) lines.push(firstLine);
    let closed = false;
    while (++nextLine < endLine) {
      const lineStart = (state.bMarks[nextLine] ?? 0) + (state.tShift[nextLine] ?? 0);
      const lineEnd = state.eMarks[nextLine] ?? 0;
      if ((state.sCount[nextLine] ?? 0) < state.blkIndent) break; // left the enclosing container
      const line = state.src.slice(lineStart, lineEnd);
      if (line.trimEnd().endsWith('$$')) {
        const before = line.trimEnd().slice(0, -2);
        if (before.trim()) lines.push(before);
        closed = true;
        break;
      }
      lines.push(state.src.slice(state.bMarks[nextLine] ?? 0, lineEnd));
    }
    if (!closed) return false;
    content = lines.join('\n');
  }
  if (silent) return true;
  state.line = nextLine + 1;
  const token = state.push('math_block', 'pre', 0);
  token.block = true;
  token.markup = '$$';
  token.content = content.trim();
  token.map = [startLine, state.line];
  return true;
}

function math(md: MarkdownIt): void {
  md.inline.ruler.after('escape', 'satchel_math_inline', mathInline);
  md.block.ruler.after('fence', 'satchel_math_block', mathBlock, {
    alt: ['paragraph', 'reference', 'blockquote', 'list'],
  });
  const esc = md.utils.escapeHtml;
  md.renderer.rules.math_inline = (tokens, idx) =>
    `<code class="math math-inline">${esc(tokens[idx]?.content ?? '')}</code>`;
  md.renderer.rules.math_inline_display = (tokens, idx) =>
    `<code class="math math-display">${esc(tokens[idx]?.content ?? '')}</code>`;
  md.renderer.rules.math_block = (tokens, idx) =>
    `<pre class="math math-display"><code>${esc(tokens[idx]?.content ?? '')}</code></pre>\n`;
}

// ---- Tables: markdown-it writes alignment as `style="text-align:…"`, and the sanitizer drops every style attribute ----

function tableAlign(md: MarkdownIt): void {
  md.core.ruler.push('satchel_table_align', (state: StateCore) => {
    for (const t of state.tokens) {
      if (t.type !== 'th_open' && t.type !== 'td_open') continue;
      const style = t.attrGet('style');
      const m = typeof style === 'string' ? /^text-align:(left|center|right)$/.exec(style) : null;
      if (!t.attrs) continue;
      t.attrs = t.attrs.filter(([name]) => name !== 'style');
      if (m?.[1]) t.attrSet('align', m[1]);
    }
  });
}
