// HTML → Markdown (spec §4.5) with our own Turndown and rules ported from Defuddle (ADR-0003 addendum).
//
// Ported from Defuddle 0.19.4, src/markdown.ts (commit d4c4bad), https://github.com/kepano/defuddle
// MIT License. Copyright (c) 2025 Steph Ango (@kepano). See THIRD_PARTY_NOTICES.md for the full notice.
//
// Changes from upstream, to meet §4.5:
// - Figures keep the image title, and the caption becomes an italic line.
// - <mark> is kept as inline HTML instead of Obsidian's ==highlight==.
// - YouTube/X embeds and other <iframe>/<video>/<audio> become a plain link line, not ![](url) embeds.
//   <svg> is dropped; only <sup>, <sub>, and <mark> are kept as HTML.
// - Task items are detected by their checkbox, since Defuddle strips the task-list classes.
// - Empty and whitespace-only links are removed in the link rule.
// - MathML → LaTeX conversion (mathml-to-latex) isn't ported: the core bundle only keeps LaTeX the page has.
// - Conversion errors throw instead of returning a "Partial conversion…" string.

import TurndownService from 'turndown';
import { isDirectTableChild, isElement, isTextNode } from './dom.ts';

type El = HTMLElement;

const WIDTH_DESCRIPTOR_RE = /^(\d+)w,?$/;
const DENSITY_DESCRIPTOR_RE = /^\d+(?:\.\d+)?x,?$/;

// MathML element names, used to tell whether a <math> has real MathML (vs. only a text annotation).
const MATHML_NODE_NAMES = new Set([
  'annotation',
  'maction',
  'math',
  'menclose',
  'merror',
  'mfenced',
  'mfrac',
  'mi',
  'mmultiscripts',
  'mn',
  'mo',
  'mover',
  'mpadded',
  'mphantom',
  'mprescripts',
  'mroot',
  'mrow',
  'ms',
  'mspace',
  'msqrt',
  'mstyle',
  'msub',
  'msubsup',
  'msup',
  'mtable',
  'mtd',
  'mtext',
  'mtr',
  'munder',
  'munderover',
  'none',
  'semantics',
]);

// MathML whose structure a flat data-latex/alttext can't represent faithfully.
const COMPLEX_MATHML_NODE_NAMES = new Set([
  'menclose',
  'mfrac',
  'mmultiscripts',
  'mover',
  'mroot',
  'msqrt',
  'msub',
  'msubsup',
  'msup',
  'mtable',
  'mtd',
  'mtr',
  'munder',
  'munderover',
]);

// A run of blockquote lines with only `>` markers and whitespace. Keeps the first line of each run.
const BLANK_QUOTE_LINE_RUN = /^([ \t]*>[ \t>]*)(?:\n[ \t]*>[ \t>]*)+$/gm;

export function isDangerousUrl(url: string): boolean {
  // biome-ignore lint/suspicious/noControlCharactersInRegex: browsers ignore control characters in URL schemes
  const normalized = url.replace(/[\s\u0000-\u001F]+/g, '').toLowerCase();
  if (/^(?:javascript|vbscript|blob):/.test(normalized)) return true;
  return normalized.startsWith('data:') && !normalized.startsWith('data:image/');
}

function formatLinkDestination(href: string): string {
  if (!/\s/.test(href)) return href.replace(/([()])/g, '\\$1');
  return `<${href.replace(/>/g, '\\>')}>`;
}

function formatLinkTitle(title: string | null): string {
  if (!title) return '';
  return ` "${title.replace(/(\n+\s*)+/g, '\n').replace(/"/g, '\\"')}"`;
}

/** The widest `w` candidate in `srcset` (tokenized on whitespace: CDN URLs can contain commas), else `src`. */
function bestImageSrc(node: El): string {
  const srcset = node.getAttribute('srcset');
  if (srcset) {
    let bestUrl = '';
    let bestWidth = 0;
    let urlParts: string[] = [];
    for (const token of srcset.trim().split(/\s+/)) {
      const widthMatch = token.match(WIDTH_DESCRIPTOR_RE);
      if (widthMatch) {
        const width = Number.parseInt(widthMatch[1] ?? '0', 10);
        const url = urlParts.join(' ').replace(/^,\s*/, '');
        if (url && width > bestWidth) {
          bestWidth = width;
          bestUrl = url;
        }
        urlParts = [];
      } else if (DENSITY_DESCRIPTOR_RE.test(token)) {
        urlParts = [];
      } else {
        urlParts.push(token);
      }
    }
    if (bestUrl) return bestUrl;
  }
  return node.getAttribute('src') || '';
}

function imageMarkdown(node: El): string {
  const src = bestImageSrc(node);
  if (!src || isDangerousUrl(src)) return '';
  const alt = (node.getAttribute('alt') || '').replace(/([[\]])/g, '\\$1');
  return `![${alt}](${formatLinkDestination(src)}${formatLinkTitle(node.getAttribute('title'))})`;
}

const children = (node: Node): Element[] => Array.from((node as El).children ?? []);

/**
 * Convert one HTML string. Pass HTML, never DOM nodes, so Node (Turndown's domino) and browsers (DOMParser)
 * take the same path (Spike C).
 */
export function htmlToMarkdown(html: string): string {
  const td = new TurndownService({
    headingStyle: 'atx',
    hr: '---',
    bulletListMarker: '-',
    codeBlockStyle: 'fenced',
    emDelimiter: '*',
    strongDelimiter: '**',
    preformattedCode: true,
    // A <math> carrying only data-latex has no text, so Turndown treats it (and a <p> holding only it) as
    // blank and would drop it. Render the math instead.
    blankReplacement(_content, node) {
      const el = node as El;
      const isBlock = (node as { isBlock?: boolean }).isBlock === true;
      const maths =
        el.nodeName.toLowerCase() === 'math' ? [el] : Array.from(el.querySelectorAll?.('math[data-latex]') ?? []);
      if (maths.length === 0) return isBlock ? '\n\n' : '';
      const out = maths.map((m) => mathReplacement(m as El)).join(' ');
      return isBlock ? `\n\n${out.trim()}\n\n` : out;
    },
  });
  // Turndown's DOM types don't line up with the rule callbacks we write against plain DOM elements.
  const convert = (fragment: string) => td.turndown(fragment);

  // Escape "<" that opens a tag (a post titled "Monte<video>") so CommonMark renderers don't treat it as
  // raw HTML. Autolinks like <a@b.com> and "a < b" are left alone. Kept elements are nodes, not text.
  const baseEscape = td.escape.bind(td);
  td.escape = (s: string) => baseEscape(s).replace(/<(?=\/?[A-Za-z][A-Za-z0-9-]*(?:\s|\/?>))/g, '\\<');

  // ATX headings. Turndown escapes "1." and "- " at the start of any line because they could start a list;
  // inside a heading they can't, so the backslash is noise.
  td.addRule('heading', {
    filter: ['h1', 'h2', 'h3', 'h4', 'h5', 'h6'],
    replacement(content, node) {
      const text = content
        .trim()
        .replace(/^(\d+)\\\./, '$1.')
        .replace(/^\\([-+])/, '$1');
      return text ? `\n\n${'#'.repeat(Number(node.nodeName.charAt(1)))} ${text}\n\n` : '';
    },
  });

  td.addRule('table', {
    filter: 'table',
    replacement(content, node) {
      const table = node as El;
      if (
        table.classList.contains('ltx_equation') ||
        table.classList.contains('ltx_eqn_table') ||
        table.classList.contains('numblk')
      ) {
        return handleNestedEquations(table);
      }

      // Layout tables: nested tables (querySelectorAll includes the node itself in Turndown's DOM, so filter it)
      // or at most one direct cell. Flatten their cells instead of emitting a broken row.
      const hasNestedTables = Array.from(table.querySelectorAll('table')).some((t) => t !== table);
      const directCells = Array.from(table.querySelectorAll('td, th')).filter((el) => isDirectTableChild(el, table));
      if (hasNestedTables || directCells.length <= 1) {
        const directRows = Array.from(table.querySelectorAll('tr')).filter((el) => isDirectTableChild(el, table));
        const cellCounts = directRows.map((tr) => directCells.filter((cell) => cell.parentNode === tr).length);
        const isSingleColumn = directRows.length > 0 && new Set(cellCounts).size === 1 && (cellCounts[0] ?? 0) <= 1;
        if (isSingleColumn || hasNestedTables) {
          return `\n\n${convert(directCells.map((cell) => cell.innerHTML).join(''))}\n\n`;
        }
      }

      // colspan/rowspan can't be expressed in a Markdown table, so keep a cleaned HTML table.
      if (
        Array.from(table.querySelectorAll('td, th')).some((c) => c.hasAttribute('colspan') || c.hasAttribute('rowspan'))
      ) {
        return `\n\n${cleanupTableHTML(table)}\n\n`;
      }

      const rowElements = Array.from(table.querySelectorAll('tr')).filter((tr) => isDirectTableChild(tr, table));
      const rows = rowElements.map((row) =>
        Array.from(row.querySelectorAll('td, th'))
          .filter((cell) => cell.parentNode === row)
          .map((cell) => convert(cell.innerHTML).replace(/\s+/g, ' ').trim().replace(/\|/g, '\\|')),
      );
      if (rows.length === 0) return content;

      // The separator row fixes a Markdown table's width, so size every row to the widest one.
      const columnCount = Math.max(...rows.map((r) => r.length));
      if (columnCount === 0) return content;
      const formatRow = (cells: string[]) =>
        `| ${[...cells, ...Array<string>(Math.max(0, columnCount - cells.length)).fill('')].join(' | ')} |`;
      const separatorRow = `| ${Array<string>(columnCount).fill('---').join(' | ')} |`;
      return `\n\n${[formatRow(rows[0] ?? []), separatorRow, ...rows.slice(1).map(formatRow)].join('\n')}\n\n`;
    },
  });

  td.remove(['style', 'script', 'noscript', 'template', 'canvas', 'form', 'select', 'textarea']);
  td.remove((node) => node.nodeName.toLowerCase() === 'svg');
  td.keep(['sup', 'sub', 'mark']);
  td.addRule('button', { filter: 'button', replacement: (content) => content });

  td.addRule('list', {
    filter: ['ul', 'ol'],
    replacement(content, node) {
      const parent = node.parentNode;
      const isTopLevel = !(parent && (parent.nodeName === 'UL' || parent.nodeName === 'OL'));
      return `${isTopLevel ? '\n' : ''}${content.trim()}\n`;
    },
  });

  // Nested items are tab-indented (as in Defuddle and Obsidian), relative to their parent item.
  td.addRule('listItem', {
    filter: 'li',
    replacement(content, node, options) {
      const li = node as El;
      // Defuddle strips the task-list classes but keeps the checkbox, so the checkbox alone marks a task item.
      const checkbox = Array.from(li.querySelectorAll('input[type="checkbox"]')).find((input) => {
        let parent = input.parentNode;
        while (parent && parent.nodeName !== 'LI') parent = parent.parentNode;
        return parent === li;
      });
      const taskMarker = checkbox ? (checkbox.hasAttribute('checked') ? '[x] ' : '[ ] ') : '';

      // Drop blank lines to keep the list tight, except inside a fenced code block, where they're content.
      let inFence = false;
      const body = content
        .replace(/\n+$/, '')
        .split('\n')
        .filter((line) => {
          if (/^\s*(?:`{3,}|~{3,})/.test(line)) inFence = !inFence;
          return inFence || line.length > 0;
        })
        .join('\n\t');

      // Nesting comes only from the parent item, which tab-indents every line of its content. (Upstream also
      // prefixed tabs for the absolute depth, which indented every child after the first one level too deep.)
      const parent = li.parentNode as El | null;
      let prefix = `${options.bulletListMarker} `;
      if (parent?.nodeName === 'OL') {
        const start = parent.getAttribute('start');
        const index = children(parent).indexOf(li) + 1;
        prefix = `${start ? Number(start) + index - 1 : index}. `;
      }
      return `${prefix}${taskMarker}${body.trim()}${li.nextSibling && !/\n$/.test(body) ? '\n' : ''}`;
    },
  });

  td.addRule('figure', {
    filter: 'figure',
    replacement(content, node) {
      const figure = node as El;
      const img = figure.querySelector('img');
      if (!img) return content;

      // A figure with <p> outside its <figcaption> is a content wrapper (Medium), not an image figure.
      const hasParagraphsOutsideCaption = Array.from(figure.querySelectorAll('p')).some((p) => {
        for (let a = p.parentNode; a && a !== figure; a = a.parentNode) if (a.nodeName === 'FIGCAPTION') return false;
        return true;
      });
      if (hasParagraphsOutsideCaption) return content;

      const image = imageMarkdown(img as El);
      const figcaption = figure.querySelector('figcaption');
      let caption = '';
      if (figcaption) {
        const tag = figcaption.querySelector('.ltx_tag_figure')?.textContent?.trim() ?? '';
        caption = `${tag} ${convert(figcaption.innerHTML).replace(/\s*\n+\s*/g, ' ')}`.trim();
      }
      if (!caption) return image ? `\n\n${image}\n\n` : '';
      const delimiter = caption.includes('*') ? '_' : '*';
      return `\n\n${image}\n\n${delimiter}${caption}${delimiter}\n\n`;
    },
  });

  td.addRule('image', { filter: 'img', replacement: (_content, node) => imageMarkdown(node as El) });

  // Embedded media becomes a link on its own line. YouTube and X get their canonical page URL.
  td.addRule('embeds', {
    filter: ['iframe', 'video', 'audio', 'embed', 'object'],
    replacement(_content, node) {
      const el = node as El;
      const src =
        el.getAttribute('src') || el.getAttribute('data') || el.querySelector('source[src]')?.getAttribute('src') || '';
      if (!src || isDangerousUrl(src)) return '';
      const youtube = src.match(
        /(?:https?:\/\/)?(?:www\.)?(?:youtube\.com|youtube-nocookie\.com|youtu\.be)\/(?:embed\/|watch\?v=)?([a-zA-Z0-9_-]+)/,
      );
      if (youtube?.[1]) return `\n\n[YouTube video](https://www.youtube.com/watch?v=${youtube[1]})\n\n`;
      const tweet = src.match(/(?:https?:\/\/)?(?:www\.)?(?:twitter\.com|x\.com)\/([^/]+)\/status\/([0-9]+)/);
      if (tweet) return `\n\n[Post on X](https://x.com/${tweet[1]}/status/${tweet[2]})\n\n`;
      const tweetEmbed = src.match(/(?:https?:\/\/)?(?:platform\.)?twitter\.com\/embed\/Tweet\.html\?.*?id=([0-9]+)/);
      if (tweetEmbed) return `\n\n[Post on X](https://x.com/i/status/${tweetEmbed[1]})\n\n`;
      const label = el.nodeName === 'VIDEO' ? 'Video' : el.nodeName === 'AUDIO' ? 'Audio' : 'Embedded content';
      return `\n\n[${label}](${formatLinkDestination(src)})\n\n`;
    },
  });

  td.addRule('strikethrough', {
    filter: ['del', 's', 'strike'] as (keyof HTMLElementTagNameMap)[],
    replacement: (content) => `~~${content}~~`,
  });

  td.addRule('link', {
    filter: 'a',
    replacement(content, node) {
      const a = node as El;
      const href = a.getAttribute('href');
      if (content.trim() === '') return '';
      if (!href || isDangerousUrl(href)) return content;
      return `[${content}](${formatLinkDestination(href)}${formatLinkTitle(a.getAttribute('title'))})`;
    },
  });

  // A link wrapping a heading and more content: emit the heading, the rest, then a link to the original.
  td.addRule('complexLinkStructure', {
    filter: (node) =>
      node.nodeName === 'A' &&
      node.childNodes.length > 1 &&
      Array.from(node.childNodes).some((child) => /^H[1-6]$/.test(child.nodeName)),
    replacement(content, node) {
      const a = node as El;
      const href = a.getAttribute('href');
      const heading = a.querySelector('h1, h2, h3, h4, h5, h6');
      const headingMarkdown = heading ? convert(heading.outerHTML) : '';
      heading?.remove();
      let markdown = `${headingMarkdown}\n\n${convert(a.innerHTML)}\n\n`;
      if (href && !isDangerousUrl(href)) {
        markdown += `[View original](${formatLinkDestination(href)}${formatLinkTitle(a.getAttribute('title'))})`;
      }
      return markdown || content;
    },
  });

  td.addRule('arXivEnumerate', {
    filter: (node) => node.nodeName === 'OL' && (node as El).classList.contains('ltx_enumerate'),
    replacement(_content, node) {
      const items = children(node).map(
        (item, index) =>
          `${index + 1}. ${convert(item.innerHTML.replace(/^<span class="ltx_tag ltx_tag_item">\d+\.<\/span>\s*/, ''))}`,
      );
      return `\n\n${items.join('\n\n')}\n\n`;
    },
  });

  // Defuddle standardizes footnote references to <sup id="fnref:N">.
  td.addRule('citations', {
    filter: (node) => node.nodeName === 'SUP' && ((node as El).getAttribute('id') ?? '').startsWith('fnref:'),
    replacement: (_content, node) =>
      `[^${((node as El).getAttribute('id') ?? '').replace('fnref:', '').split('-')[0]}]`,
  });

  // ...and the footnotes themselves to <div id="footnotes"><ol><li id="fn:N">.
  td.addRule('footnotesList', {
    filter: (node) => node.nodeName === 'OL' && (node.parentNode as El | null)?.getAttribute?.('id') === 'footnotes',
    replacement(_content, node) {
      const references = children(node).map((li) => {
        const liId = li.getAttribute('id');
        let id: string | undefined;
        if (liId !== null) {
          if (liId.startsWith('fn:')) id = liId.replace('fn:', '');
          else
            id =
              liId
                .split('/')
                .pop()
                ?.match(/cite_note-(.+)/)?.[1] ?? liId;
        }
        const sup = li.querySelector('sup');
        if (sup && sup.textContent?.trim() === id) sup.remove();
        const text = convert(li.innerHTML).replace(/\s*↩︎$/, '').trim();
        return `[^${id?.toLowerCase()}]: ${text}`;
      });
      return `\n\n${references.join('\n\n')}\n\n`;
    },
  });

  // Footnote backlinks.
  td.addRule('removals', {
    filter: (node) =>
      isElement(node) &&
      ((node as El).getAttribute('href')?.includes('#fnref') === true ||
        (node as El).classList.contains('footnote-backref')),
    replacement: () => '',
  });

  td.addRule('preformattedCode', {
    filter: 'pre',
    replacement(content, node) {
      const pre = node as El;
      const code = pre.querySelector('code');
      if (!code) return content;
      const language =
        code.getAttribute('data-lang') ||
        code.getAttribute('data-language') ||
        code.getAttribute('class')?.match(/(?:^|\s)(?:language|lang)-([\w+#-]+)/)?.[1] ||
        pre.getAttribute('data-language') ||
        '';
      // Backslash escapes are literal inside a fence, so grow the fence past the longest backtick run instead.
      const text = (code.textContent || '').replace(/^\n+|\s+$/g, '');
      const fenceSize = (text.match(/^ {0,3}`{3,}/gm) ?? []).reduce(
        (size, run) => Math.max(size, run.trim().length + 1),
        3,
      );
      const fence = '`'.repeat(fenceSize);
      return `\n\n${fence}${language}\n${text}\n${fence}\n\n`;
    },
  });

  td.addRule('math', {
    filter: (node) =>
      node.nodeName.toLowerCase() === 'math' ||
      (isElement(node) &&
        ['mwe-math-element', 'mwe-math-fallback-image-inline', 'mwe-math-fallback-image-display'].some((c) =>
          (node as El).classList.contains(c),
        )),
    replacement: (_content, node) => mathReplacement(node as El),
  });

  function mathReplacement(el: El): string {
    const latex = extractLatex(el).trim();
    const isInTable = typeof el.closest === 'function' && el.closest('table') !== null;
    const parent = el.parentNode as El | null;
    const isBlock =
      !isInTable &&
      (el.getAttribute('display') === 'block' ||
        el.classList.contains('mwe-math-fallback-image-display') ||
        isOnlyMathInParagraph(el) ||
        (parent?.classList?.contains('mwe-math-element') === true &&
          parent.previousSibling?.nodeName.toLowerCase() === 'p'));
    if (isBlock) return `\n$$\n${formatBlockLatex(latex)}\n$$\n`;

    // Inline: add a space on a side only where the neighbor would otherwise run into the $.
    const prev = el.previousSibling;
    const next = el.nextSibling;
    const prevChar = prev?.textContent?.slice(-1) ?? '';
    const nextChar = next?.textContent?.[0] ?? '';
    const isStart = !prev || (isTextNode(prev) && prev.textContent?.trim() === '');
    const isEnd = !next || (isTextNode(next) && next.textContent?.trim() === '');
    // Only next to a letter or digit: "$x$, called" needs no space before the comma.
    const left = !isStart && /[\p{L}\p{N}]/u.test(prevChar) ? ' ' : '';
    const right = !isEnd && /[\p{L}\p{N}]/u.test(nextChar) ? ' ' : '';
    return `${left}$${latex}$${right}`;
  }

  td.addRule('katex', {
    filter: (node) =>
      isElement(node) && ((node as El).classList.contains('math') || (node as El).classList.contains('katex')),
    replacement(_content, node) {
      const el = node as El;
      const latex =
        el.getAttribute('data-latex') ||
        el.querySelector('.katex-mathml annotation[encoding="application/x-tex"]')?.textContent ||
        el.textContent?.trim() ||
        '';
      const mathElement = el.querySelector('.katex-mathml math');
      const isInline =
        el.classList.contains('math-inline') ||
        (mathElement !== null && mathElement.getAttribute('display') !== 'block');
      return isInline ? `$${latex}$` : `\n$$\n${latex}\n$$\n`;
    },
  });

  // Defuddle standardizes GitHub alerts, Bootstrap alerts, and callout asides to div.callout[data-callout].
  td.addRule('callout', {
    filter: (node) =>
      isElement(node) && !!(node as El).getAttribute('data-callout') && (node as El).classList.contains('callout'),
    replacement(_content, node) {
      const el = node as El;
      const type = el.getAttribute('data-callout') || 'note';
      const fold = el.getAttribute('data-callout-fold');
      const foldIndicator = fold === '-' || fold === '+' ? fold : '';
      const title =
        el.querySelector('.callout-title-inner')?.textContent?.trim() || type.charAt(0).toUpperCase() + type.slice(1);
      el.querySelector('.callout-title')?.remove();
      const body = convert((el.querySelector('.callout-content') ?? el).innerHTML);
      const quoted = body
        .trim()
        .split('\n')
        .map((line) => (line ? `> ${line}` : '>'))
        .join('\n');
      return `\n\n> [!${type}]${foldIndicator} ${title}\n${quoted}\n\n`;
    },
  });

  function handleNestedEquations(element: El): string {
    return Array.from(element.querySelectorAll('math'))
      .map((math) => {
        const latex =
          math.querySelector('annotation[encoding="application/x-tex"]')?.textContent?.trim() ||
          math.getAttribute('alttext')?.trim();
        if (!latex) return '';
        return math.closest('.ltx_eqn_inline, .mwe-math-element-inline') !== null ? `$${latex}$` : `\n$$\n${latex}\n$$`;
      })
      .join('\n\n');
  }

  function cleanupTableHTML(element: El): string {
    const allowed = ['src', 'href', 'align', 'width', 'height', 'rowspan', 'colspan', 'scope', 'valign', 'headers'];
    const clean = (el: Element) => {
      for (const attr of Array.from(el.attributes)) if (!allowed.includes(attr.name)) el.removeAttribute(attr.name);
      for (const child of Array.from(el.childNodes)) if (isElement(child)) clean(child);
    };
    const copy = element.cloneNode(true) as El;
    clean(copy);
    // outerHTML encodes & as &amp;, which breaks LaTeX alignment inside math; the output is Markdown, not HTML.
    return copy.outerHTML.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
  }

  return finish(convert(html.replace(/<wbr\s*\/?>/gi, '')));
}

/** Document-level cleanup after conversion. */
function finish(converted: string): string {
  let markdown = converted;
  // The body starts with our own `# title`, so drop a leading H1 the content brought along.
  markdown = markdown.replace(/^# .+\n+/, '');
  // Empty links like [](example.com) that slipped through, but not images.
  markdown = markdown.replace(/\n*(?<!!)\[\]\([^)]+\)\n*/g, '');
  // "Yey!![IMG](url)" → "Yey! ![IMG](url)", so the "!" isn't read as part of the image.
  markdown = markdown.replace(/!(?=!\[|\[!\[)/g, '! ');
  // Whitespace-only lines (stray <br>s) become blank; elsewhere keep Turndown's two-space hard breaks.
  markdown = markdown.replace(/^[ \t]+$/gm, '');
  markdown = markdown.replace(/[ \t]+$/gm, (spaces) => (spaces === '  ' ? spaces : ''));
  markdown = markdown.replace(/\n{3,}/g, '\n\n');
  markdown = markdown.replace(BLANK_QUOTE_LINE_RUN, '$1');
  return markdown.trim();
}

function extractLatex(element: El): string {
  const annotation = element.querySelector('annotation[encoding="application/x-tex"]')?.textContent?.trim();
  if (annotation) return annotation;
  const latex = element.getAttribute('data-latex');
  const alttext = element.getAttribute('alttext');
  const hasMathML = hasMathMLChildren(element);
  const hasComplex = hasComplexMathMLChildren(element);
  if (latex && (!hasMathML || isTrustworthyLatexAttribute(latex, hasComplex))) return latex.trim();
  if (alttext && (!hasMathML || isTrustworthyLatexAttribute(alttext, hasComplex))) return alttext.trim();
  return (latex ?? alttext ?? '').trim();
}

function hasMathMLChildren(element: El): boolean {
  return children(element).some(
    (child) =>
      child.namespaceURI === 'http://www.w3.org/1998/Math/MathML' ||
      MATHML_NODE_NAMES.has(child.nodeName.toLowerCase()),
  );
}

function hasComplexMathMLChildren(element: Element): boolean {
  return (
    COMPLEX_MATHML_NODE_NAMES.has(element.nodeName.toLowerCase()) || children(element).some(hasComplexMathMLChildren)
  );
}

function isTrustworthyLatexAttribute(value: string, hasComplexMathML: boolean): boolean {
  if (/\\[a-zA-Z]+|[_^{}]|[$&]|\\\\|\\begin\{/.test(value)) return true;
  const trimmed = value.trim();
  if (!trimmed || hasComplexMathML) return false;
  // Rendered prose such as "fan-outfan-in" can end up in data-latex; prefer MathML for those.
  return !/[a-zA-Z]{3,}-[a-zA-Z]{2,}/.test(trimmed);
}

function formatBlockLatex(value: string): string {
  const latex = value.trim();
  if (!latex) return latex;
  const hasEnvironment = (s: string) => /\\begin\{[^}]+\}/.test(s);
  const bareMatrix = latex.match(/^\\begin\{matrix\}([\s\S]*?)\\end\{matrix\}$/);
  if (bareMatrix && !hasEnvironment(bareMatrix[1] ?? ''))
    return `\\begin{aligned}\n${(bareMatrix[1] ?? '').trim()}\n\\end{aligned}`;
  if (hasEnvironment(latex)) return latex;
  if (latex.includes('\\\\') || latex.includes('&')) return `\\begin{aligned}\n${latex}\n\\end{aligned}`;
  return latex;
}

function isOnlyMathInParagraph(element: El): boolean {
  const parent = element.parentNode as El | null;
  if (parent?.nodeName.toLowerCase() !== 'p') return false;
  const elementChildren = children(parent);
  if (elementChildren.length !== 1 || elementChildren[0] !== element) return false;
  return Array.from(parent.childNodes).every(
    (child) => child === element || (isTextNode(child) && child.textContent?.trim() === ''),
  );
}
