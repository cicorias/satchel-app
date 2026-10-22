import { describe, expect, test } from 'vitest';
import { createRenderer, render, version } from '../src/index.ts';
import { expectSafe, parse, renderer, testWindow } from './helpers.ts';

const r = renderer();
const html = (md: string, opts: Parameters<typeof r.render>[1] = {}) => {
  const out = r.render(md, opts).html;
  expectSafe(out);
  return out;
};
const dom = (md: string, opts: Parameters<typeof r.render>[1] = {}) => parse(html(md, opts));

test('exports a version', () => {
  expect(version).toMatch(/^\d+\.\d+\.\d+$/);
});

describe('the safety check itself', () => {
  test.each([
    '<img src=x onerror=alert(1)>',
    '<script>alert(1)</script>',
    '<a href="javascript:alert(1)">x</a>',
    '<p style="color:red">x</p>',
    '<svg></svg>',
    '<input type="text" disabled>',
  ])('rejects %s', (bad) => {
    expect(() => expectSafe(bad)).toThrow();
  });
});

describe('frontmatter', () => {
  const file = '---\nid: u_1\ntitle: "How: CloudKit"\ntags: [a, b]\n---\n\n# Heading\n\nBody.\n';

  test('is stripped from the body and returned raw', () => {
    const out = r.render(file);
    expect(out.html).toBe('<h1>Heading</h1>\n<p>Body.</p>\n');
    expect(out.frontmatter).toBe('id: u_1\ntitle: "How: CloudKit"\ntags: [a, b]');
  });

  test('handles CRLF line endings and a byte-order mark', () => {
    const out = r.render(`﻿${file.replace(/\n/g, '\r\n')}`);
    expect(out.frontmatter).toBe('id: u_1\r\ntitle: "How: CloudKit"\r\ntags: [a, b]');
    expect(parse(out.html).querySelector('h1')?.textContent).toBe('Heading');
  });

  test('an empty block is still frontmatter', () => {
    expect(r.render('---\n---\nBody').frontmatter).toBe('');
  });

  test('is absent when the file has none', () => {
    const out = r.render('# Title\n\n---\n\nAfter a rule.');
    expect(out.frontmatter).toBeNull();
    expect(out.html).toContain('<hr>');
  });

  test('an unclosed block is not frontmatter', () => {
    const out = r.render('---\ntitle: x\n\nBody');
    expect(out.frontmatter).toBeNull();
    expect(out.html).toContain('<hr>');
  });

  test('a fence must be the first line', () => {
    expect(r.render('\n---\na: 1\n---\n').frontmatter).toBeNull();
  });
});

describe('GFM', () => {
  test('tables keep alignment without style attributes', () => {
    const root = dom('| L | C | R |\n|:--|:-:|--:|\n| 1 | 2 | 3 |');
    const cells = Array.from(root.querySelectorAll('th')).map((th) => th.getAttribute('align'));
    expect(cells).toEqual(['left', 'center', 'right']);
    expect(root.querySelector('td')?.textContent).toBe('1');
    expect(root.querySelector('[style]')).toBeNull();
  });

  test('strikethrough', () => {
    expect(html('~~gone~~')).toBe('<p><s>gone</s></p>\n');
  });

  test('task lists render disabled checkboxes', () => {
    const root = dom('- [ ] todo\n- [x] done\n- [X] also done\n- plain');
    expect(root.querySelector('ul')?.className).toBe('contains-task-list');
    const items = Array.from(root.querySelectorAll('li'));
    expect(items.map((li) => li.className)).toEqual(['task-list-item', 'task-list-item', 'task-list-item', '']);
    const boxes = Array.from(root.querySelectorAll('input'));
    expect(boxes.map((b) => b.hasAttribute('checked'))).toEqual([false, true, true]);
    expect(boxes.every((b) => b.type === 'checkbox' && b.disabled)).toBe(true);
    expect(items[0]?.textContent?.trim()).toBe('todo');
  });

  test('task lists work in loose and nested lists', () => {
    const root = dom('1. [x] first\n\n2. second\n   - [ ] nested');
    expect(root.querySelector('ol')?.className).toBe('contains-task-list');
    expect(root.querySelector('ul')?.className).toBe('contains-task-list');
    expect(root.querySelectorAll('input')).toHaveLength(2);
  });

  test('brackets that are not a task marker are left alone', () => {
    expect(dom('- [link] text\n- [ ]no space').querySelector('input')).toBeNull();
  });

  test('bare URLs are linkified', () => {
    expect(dom('see https://example.com/x').querySelector('a')?.getAttribute('href')).toBe('https://example.com/x');
  });
});

describe('code', () => {
  test('fences carry the language class and escape their content', () => {
    const root = dom('```python\nprint("<b>hi</b>")\n```');
    const code = root.querySelector('pre > code');
    expect(code?.className).toBe('language-python');
    expect(code?.textContent).toBe('print("<b>hi</b>")\n');
    expect(root.querySelector('b')).toBeNull();
  });

  test('a fence without a language has no class', () => {
    expect(dom('```\nx\n```').querySelector('code')?.hasAttribute('class')).toBe(false);
  });

  test('inline code', () => {
    expect(html('use `a < b`')).toBe('<p>use <code>a &lt; b</code></p>\n');
  });
});

describe('footnotes', () => {
  const root = () => dom('Claim[^1] and another[^note].\n\n[^1]: First.\n[^note]: Second *note*.');

  test('references link to the notes and back', () => {
    const refs = Array.from(root().querySelectorAll('sup.footnote-ref a'));
    expect(refs).toHaveLength(2);
    const doc = root();
    for (const ref of Array.from(doc.querySelectorAll('sup.footnote-ref a'))) {
      const target = ref.getAttribute('href')?.slice(1) ?? '';
      const note = doc.querySelector(`[id="${target}"]`);
      expect(note?.tagName).toBe('LI');
      const back = note?.querySelector('a.footnote-backref')?.getAttribute('href')?.slice(1);
      expect(doc.querySelector(`[id="${back}"]`)).toBe(ref);
    }
  });

  test('notes are rendered in a footnotes section with inline Markdown', () => {
    const section = root().querySelector('section.footnotes');
    expect(section?.querySelectorAll('li')).toHaveLength(2);
    expect(section?.querySelector('em')?.textContent).toBe('note');
  });

  test('fragment links get no target and no rel', () => {
    const a = root().querySelector('sup a');
    expect(a?.hasAttribute('target')).toBe(false);
    expect(a?.hasAttribute('rel')).toBe(false);
  });

  test('docId keeps ids distinct across documents', () => {
    const a = parse(r.render('x[^1]\n\n[^1]: n', { docId: 'doc7' }).html).querySelector('sup a');
    expect(a?.getAttribute('href')).toBe('#user-content-fn-doc7-1');
  });
});

describe('callouts', () => {
  test('type, title, and body', () => {
    const root = dom('> [!warning] Be *careful*\n> Body line.\n>\n> More.');
    const callout = root.querySelector('div.callout');
    expect(callout?.getAttribute('data-callout')).toBe('warning');
    expect(callout?.querySelector('.callout-title')?.innerHTML).toBe('Be <em>careful</em>');
    const paragraphs = Array.from(callout?.querySelectorAll('.callout-content > p') ?? []).map((p) => p.textContent);
    expect(paragraphs).toEqual(['Body line.', 'More.']);
    expect(root.querySelector('blockquote')).toBeNull();
  });

  test('the title defaults to the capitalized type, which is lowercased', () => {
    const callout = dom('> [!NOTE]\n> Body.').querySelector('.callout');
    expect(callout?.getAttribute('data-callout')).toBe('note');
    expect(callout?.querySelector('.callout-title')?.textContent).toBe('Note');
    expect(callout?.querySelector('.callout-content')?.textContent?.trim()).toBe('Body.');
  });

  test('a marker on its own paragraph leaves no empty paragraph', () => {
    const content = dom('> [!info]\n>\n> Body.').querySelector('.callout-content');
    expect(content?.querySelectorAll('p')).toHaveLength(1);
  });

  test('foldable callouts use <details>, open with +', () => {
    const closed = dom('> [!faq]- Why?\n> Because.').querySelector('details.callout');
    expect(closed?.hasAttribute('open')).toBe(false);
    expect(closed?.querySelector('summary.callout-title')?.textContent).toBe('Why?');
    const open = dom('> [!faq]+ Why?\n> Because.').querySelector('details.callout');
    expect(open?.hasAttribute('open')).toBe(true);
  });

  test('callouts nest', () => {
    const root = dom('> [!note] Outer\n> > [!tip] Inner\n> > Text.');
    expect(root.querySelector('.callout .callout-content .callout')?.getAttribute('data-callout')).toBe('tip');
  });

  test('ordinary blockquotes are untouched', () => {
    expect(html('> Just a quote [!not] a callout.')).toBe(
      '<blockquote>\n<p>Just a quote [!not] a callout.</p>\n</blockquote>\n',
    );
  });
});

describe('math is kept as LaTeX source', () => {
  test('inline $…$ is protected from emphasis parsing', () => {
    expect(html('Area $a_1 * b_2 * c$ here.')).toBe(
      '<p>Area <code class="math math-inline">a_1 * b_2 * c</code> here.</p>\n',
    );
  });

  test('display $$…$$ blocks', () => {
    const pre = dom('$$\n\\frac{a}{b}\n$$').querySelector('pre.math.math-display');
    expect(pre?.textContent).toBe('\\frac{a}{b}');
  });

  test('single-line $$…$$ blocks and inline display math', () => {
    expect(dom('$$x^2$$').querySelector('pre.math')?.textContent).toBe('x^2');
    expect(dom('so $$x^2$$ inline').querySelector('code.math-display')?.textContent).toBe('x^2');
  });

  test('prices and escaped dollars stay text', () => {
    expect(html('It costs $5 and $10.')).toBe('<p>It costs $5 and $10.</p>\n');
    expect(html('\\$x$ not math')).toBe('<p>$x$ not math</p>\n');
  });

  test('an unclosed $$ block is a paragraph', () => {
    expect(dom('$$\nx').querySelector('.math')).toBeNull();
  });
});

describe('links', () => {
  test('external links get rel="noopener noreferrer" and target="_blank"', () => {
    const a = dom('[x](https://example.com)').querySelector('a');
    expect(a?.getAttribute('rel')).toBe('noopener noreferrer');
    expect(a?.getAttribute('target')).toBe('_blank');
  });

  test('the target is configurable and can be omitted', () => {
    expect(dom('[x](https://example.com)', { linkTarget: '_top' }).querySelector('a')?.target).toBe('_top');
    const a = dom('[x](https://example.com)', { linkTarget: null }).querySelector('a');
    expect(a?.hasAttribute('target')).toBe(false);
    expect(a?.getAttribute('rel')).toBe('noopener noreferrer');
  });

  test('mailto and tel are allowed', () => {
    expect(dom('<mailto:a@example.com>').querySelector('a')?.getAttribute('href')).toBe('mailto:a@example.com');
    expect(dom('<a href="tel:+15555550100">call</a>').querySelector('a')?.getAttribute('href')).toBe(
      'tel:+15555550100',
    );
  });

  test('relative links lose their href (captured links are absolute)', () => {
    expect(dom('[x](/relative/path)').querySelector('a')?.hasAttribute('href')).toBe(false);
  });
});

describe('images', () => {
  const md = '![Cover](https://img.example.com/a.png "Title")';

  test('remote images are blocked by default, keeping the alt text', () => {
    const out = r.render(md);
    expectSafe(out.html);
    expect(out.blockedImages).toBe(1);
    const root = parse(out.html);
    expect(root.querySelector('img')).toBeNull();
    const span = root.querySelector('span.image-blocked');
    expect(span?.textContent).toBe('Cover');
    expect(span?.getAttribute('title')).toBe('https://img.example.com/a.png');
  });

  test('a blocked image without alt text says "Image"', () => {
    expect(dom('![](https://img.example.com/a.png)').querySelector('.image-blocked')?.textContent).toBe('Image');
  });

  test('remote images load when the toggle is on, without a referrer', () => {
    const out = r.render(md, { remoteImages: true });
    expect(out.blockedImages).toBe(0);
    const img = parse(out.html).querySelector('img');
    expect(img?.getAttribute('src')).toBe('https://img.example.com/a.png');
    expect(img?.getAttribute('alt')).toBe('Cover');
    expect(img?.getAttribute('title')).toBe('Title');
    expect(img?.getAttribute('referrerpolicy')).toBe('no-referrer');
    expect(img?.getAttribute('loading')).toBe('lazy');
  });

  test('protocol-relative images are pinned to https', () => {
    const img = dom('<img src="//img.example.com/a.png">', { remoteImages: true }).querySelector('img');
    expect(img?.getAttribute('src')).toBe('https://img.example.com/a.png');
  });

  test('blocked images inside links leave the link intact', () => {
    const a = dom('[![a](https://img.example.com/a.png)](https://example.com)').querySelector('a');
    expect(a?.querySelector('.image-blocked')?.textContent).toBe('a');
  });

  test('data:image URIs (self-contained export) always render', () => {
    const src = 'data:image/png;base64,iVBORw0KGgo=';
    const out = r.render(`![a](${src})`);
    expect(out.blockedImages).toBe(0);
    expect(parse(out.html).querySelector('img')?.getAttribute('src')).toBe(src);
  });

  test('stored asset paths go through resolveImage', () => {
    const seen: string[] = [];
    const resolveImage = (src: string) => {
      seen.push(src);
      return src === 'images/abc.png' ? 'blob:https://app.example/1234' : null;
    };
    const root = dom('![a](images/abc.png) ![b](images/missing.png)', { resolveImage });
    expect(seen).toEqual(['images/abc.png', 'images/missing.png']);
    expect(root.querySelector('img')?.getAttribute('src')).toBe('blob:https://app.example/1234');
    expect(root.querySelector('.image-missing')?.textContent).toBe('b');
  });

  test('a resolver cannot return a script URL', () => {
    expect(dom('![a](images/x.png)', { resolveImage: () => 'javascript:alert(1)' }).querySelector('img')).toBeNull();
  });

  test('relative images without a resolver are placeholders, not counted as blocked', () => {
    const out = r.render('![a](images/abc.png)');
    expect(out.blockedImages).toBe(0);
    expect(parse(out.html).querySelector('.image-missing')?.textContent).toBe('a');
  });
});

describe('inline HTML', () => {
  test('safe tags kept by Turndown survive', () => {
    const root = dom('H<sub>2</sub>O and E=mc<sup>2</sup>, <mark>hi</mark>, <kbd>Ctrl</kbd>');
    expect(root.querySelector('sub')?.textContent).toBe('2');
    expect(root.querySelector('sup')?.textContent).toBe('2');
    expect(root.querySelector('mark, kbd')).not.toBeNull();
  });

  test('html: false escapes it instead', () => {
    expect(renderer({ html: false }).render('a <sub>2</sub>').html).toBe('<p>a &lt;sub&gt;2&lt;/sub&gt;</p>\n');
  });
});

describe('DOM injection', () => {
  test('createRenderer uses globalThis.window when none is passed', () => {
    const g = globalThis as { window?: unknown };
    expect(g.window).toBeUndefined();
    expect(() => createRenderer()).toThrow(/no DOM available/);
    expect(() => render('x')).toThrow(/no DOM available/);
    g.window = testWindow;
    try {
      expect(createRenderer().render('*x*').html).toBe('<p><em>x</em></p>\n');
      expect(render('*y*').html).toBe('<p><em>y</em></p>\n');
    } finally {
      delete g.window;
    }
  });
});
