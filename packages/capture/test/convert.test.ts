import { describe, expect, test } from 'vitest';
import { htmlToMarkdown } from '../src/markdown/convert.ts';

const md = (html: string) => htmlToMarkdown(html);

describe('§4.5 conventions', () => {
  test('ATX headings, * emphasis, ** strong, - bullets', () => {
    expect(md('<h2>Section</h2><p><em>a</em> and <strong>b</strong></p><ul><li>one</li><li>two</li></ul>')).toBe(
      '## Section\n\n*a* and **b**\n\n- one\n- two',
    );
  });

  test('drops a leading H1, which the frontmatter title replaces', () => {
    expect(md('<h1>Title</h1><p>Body</p>')).toBe('Body');
    expect(md('<p>Intro</p><h1>Later</h1>')).toBe('Intro\n\n# Later');
  });

  test('nested lists are tab-indented, and ordered lists honor start', () => {
    expect(md('<ul><li>a<ul><li>b</li></ul></li><li>c</li></ul>')).toBe('- a\n\t- b\n- c');
    expect(md('<ol><li>a<ol><li>b1</li><li>b2</li></ol></li><li>c</li></ol>')).toBe('1. a\n\t1. b1\n\t2. b2\n2. c');
    expect(md('<ul><li><p>a</p><ul><li>b1</li><li>b2<ul><li>c1</li><li>c2</li></ul></li></ul></li></ul>')).toBe(
      '- a\n\t- b1\n\t- b2\n\t\t- c1\n\t\t- c2',
    );
    expect(md('<ol start="3"><li>x</li><li>y</li></ol>')).toBe('3. x\n4. y');
  });

  test('blank lines inside a code block in a list item survive', () => {
    expect(md('<ul><li><p>Run:</p><pre><code>a\n\nb</code></pre></li></ul>')).toBe('- Run:\n\t```\n\ta\n\n\tb\n\t```');
  });

  test('task items come from the checkbox (Defuddle strips the task-list classes)', () => {
    expect(
      md('<ul><li><input type="checkbox" checked> Ship it</li><li><input type="checkbox"> Test it</li></ul>'),
    ).toBe('- [x] Ship it\n- [ ] Test it');
  });

  test('strikethrough uses ~~', () => {
    expect(md('<p><del>old</del> <s>gone</s></p>')).toBe('~~old~~ ~~gone~~');
  });

  test('tables are GitHub-flavored, padded to the widest row, with pipes escaped', () => {
    expect(md('<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2 | 3</td><td>extra</td></tr></table>')).toBe(
      '| A | B |  |\n| --- | --- | --- |\n| 1 | 2 \\| 3 | extra |',
    );
  });

  test('tables with colspan stay as cleaned HTML', () => {
    expect(
      md('<table class="x"><tr><td colspan="2" style="color:red">wide</td></tr><tr><td>1</td><td>2</td></tr></table>'),
    ).toBe('<table><tbody><tr><td colspan="2">wide</td></tr><tr><td>1</td><td>2</td></tr></tbody></table>');
  });

  test('single-column layout tables are flattened', () => {
    expect(md('<table><tr><td><p>Just a layout cell</p></td></tr></table>')).toBe('Just a layout cell');
  });
});

describe('images and figures', () => {
  test('images keep alt and title, using the widest srcset candidate', () => {
    expect(
      md(
        '<p><img src="https://e.com/s.png" srcset="https://e.com/m.png 600w, https://e.com/l.png 1200w" alt="A" title="T"></p>',
      ),
    ).toBe('![A](https://e.com/l.png "T")');
  });

  test('srcset URLs with commas (CDN transforms) survive', () => {
    expect(
      md('<img srcset="https://cdn.e.com/w_424,c_limit/a.png 424w, https://cdn.e.com/w_848,c_limit/a.png 848w">'),
    ).toBe('![](https://cdn.e.com/w_848,c_limit/a.png)');
  });

  test('a figure becomes the image, then its caption as an italic line', () => {
    expect(
      md(
        '<figure><img src="https://e.com/a.png" alt="Chart" title="Q3"><figcaption>Revenue by <a href="https://e.com/q">quarter</a></figcaption></figure>',
      ),
    ).toBe('![Chart](https://e.com/a.png "Q3")\n\n*Revenue by [quarter](https://e.com/q)*');
  });

  test('a caption containing * is italicized with _', () => {
    expect(md('<figure><img src="https://e.com/a.png"><figcaption>a * b</figcaption></figure>')).toBe(
      '![](https://e.com/a.png)\n\n_a \\* b_',
    );
  });

  test('a figure that wraps paragraphs is treated as content', () => {
    expect(md('<figure><p>Paragraph one</p><img src="https://e.com/a.png"></figure>')).toBe(
      'Paragraph one\n\n![](https://e.com/a.png)',
    );
  });

  test('brackets in alt text and parentheses in URLs are escaped', () => {
    expect(md('<img src="https://e.com/a_(1).png" alt="[x]">')).toBe('![\\[x\\]](https://e.com/a_\\(1\\).png)');
  });

  test('images with dangerous URLs are dropped', () => {
    expect(md('<p>x<img src="javascript:alert(1)">y</p>')).toBe('xy');
  });
});

describe('code', () => {
  test.each([
    ['language-*', '<pre><code class="language-python">print(1)</code></pre>', '```python\nprint(1)\n```'],
    ['lang-*', '<pre><code class="lang-js">let a</code></pre>', '```js\nlet a\n```'],
    ['data-lang', '<pre><code data-lang="rust">fn main() {}</code></pre>', '```rust\nfn main() {}\n```'],
    ['no language', '<pre><code>plain</code></pre>', '```\nplain\n```'],
  ])('fenced code takes the language from %s', (_, html, expected) => {
    expect(md(html)).toBe(expected);
  });

  test('code is never escaped, and the fence outgrows backtick runs inside it', () => {
    expect(md('<pre><code>a_b *c* [d](e)\n```\nnested\n```</code></pre>')).toBe(
      '````\na_b *c* [d](e)\n```\nnested\n```\n````',
    );
  });

  test('inline code keeps its content', () => {
    expect(md('<p>Run <code>npm i *</code> now</p>')).toBe('Run `npm i *` now');
  });

  test('indentation inside code survives', () => {
    expect(md('<pre><code class="language-py">def f():\n    return 1\n</code></pre>')).toBe(
      '```py\ndef f():\n    return 1\n```',
    );
  });
});

describe('links', () => {
  test('inline links with titles', () => {
    expect(md('<p><a href="https://e.com/a" title="Say &quot;hi&quot;">A</a></p>')).toBe(
      '[A](https://e.com/a "Say \\"hi\\"")',
    );
  });

  test('empty and whitespace-only links are removed (the whitespace stays, as a browser shows it)', () => {
    expect(md('<p>a<a href="https://e.com/1"></a>b<a href="https://e.com/2">  </a>c</p>')).toBe('ab c');
  });

  test('dangerous hrefs keep only the text', () => {
    expect(md('<p><a href="javascript:alert(1)">click</a> <a href="data:text/html,x">d</a></p>')).toBe('click d');
  });

  test('URLs with parentheses or spaces are not mangled', () => {
    expect(md('<p><a href="https://en.wikipedia.org/wiki/Fish_(food)">fish</a></p>')).toBe(
      '[fish](https://en.wikipedia.org/wiki/Fish_\\(food\\))',
    );
    expect(md('<p><a href="https://e.com/a b">sp</a></p>')).toBe('[sp](<https://e.com/a b>)');
  });

  test('tag-like text is escaped so renderers do not swallow it', () => {
    expect(md('<p>Monte&lt;video&gt; and a &lt; b</p>')).toBe('Monte\\<video> and a < b');
  });
});

describe('footnotes, callouts, math (Defuddle standardized markup)', () => {
  test('footnote references and the footnote list use [^n]', () => {
    const html =
      '<p>Claim<sup id="fnref:1"><a href="#fn:1">1</a></sup>.</p><div id="footnotes"><ol><li id="fn:1"><p>Source text. <a href="#fnref:1" class="footnote-backref">↩</a></p></li></ol></div>';
    expect(md(html)).toBe('Claim[^1].\n\n[^1]: Source text.');
  });

  test('callouts become Obsidian callouts', () => {
    const html =
      '<div class="callout" data-callout="warning"><div class="callout-title"><div class="callout-title-inner">Careful</div></div><div class="callout-content"><p>Line one.</p><p>Line two.</p></div></div>';
    expect(md(html)).toBe('> [!warning] Careful\n> Line one.\n>\n> Line two.');
  });

  test('a callout without a title uses its type, and keeps the fold marker', () => {
    expect(md('<div class="callout" data-callout="tip" data-callout-fold="-"><p>Hidden</p></div>')).toBe(
      '> [!tip]- Tip\n> Hidden',
    );
  });

  test('inline and block math keep their LaTeX', () => {
    expect(md('<p>Area <math data-latex="\\pi r^2"></math> here.</p>')).toBe('Area $\\pi r^2$ here.');
    expect(md('<p><math display="block" data-latex="E = mc^2"></math></p>')).toBe('$$\nE = mc^2\n$$');
  });

  test('inline math gets a space only next to a letter or digit', () => {
    expect(md('<p>scalar<math data-latex="\\lambda"></math>, called it<math data-latex="x"></math>2</p>')).toBe(
      'scalar $\\lambda$, called it $x$ 2',
    );
  });

  test('KaTeX output uses its TeX annotation', () => {
    const html =
      '<p>Then <span class="katex"><span class="katex-mathml"><math><semantics><annotation encoding="application/x-tex">x^2</annotation></semantics></math></span></span>.</p>';
    expect(md(html)).toBe('Then $x^2$.');
  });
});

describe('kept and dropped elements', () => {
  test('sup, sub, and mark stay inline HTML', () => {
    expect(md('<p>H<sub>2</sub>O, x<sup>2</sup>, <mark>key</mark></p>')).toBe(
      'H<sub>2</sub>O, x<sup>2</sup>, <mark>key</mark>',
    );
  });

  test('embeds become links on their own line', () => {
    expect(md('<p>Watch:</p><iframe src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?si=x"></iframe>')).toBe(
      'Watch:\n\n[YouTube video](https://www.youtube.com/watch?v=dQw4w9WgXcQ)',
    );
    expect(md('<iframe src="https://x.com/kepano/status/123"></iframe>')).toBe(
      '[Post on X](https://x.com/kepano/status/123)',
    );
    expect(md('<video><source src="https://e.com/v.mp4"></video>')).toBe('[Video](https://e.com/v.mp4)');
    expect(md('<iframe src="https://maps.example.com/embed?q=1"></iframe>')).toBe(
      '[Embedded content](https://maps.example.com/embed?q=1)',
    );
  });

  test('svg, scripts, styles, and forms are dropped', () => {
    expect(
      md('<p>a</p><svg><text>x</text></svg><script>1</script><style>p{}</style><form><input></form><p>b</p>'),
    ).toBe('a\n\nb');
  });
});

describe('document cleanup', () => {
  test('three or more blank lines collapse to one blank line, and trailing whitespace goes', () => {
    expect(md('<p>a   </p><br><br><br><br><p>b</p>')).toBe('a\n\nb');
  });

  test('hard line breaks survive', () => {
    expect(md('<p>line one<br>line two</p>')).toBe('line one  \nline two');
  });

  test('"!" before an image gets a space', () => {
    expect(md('<p>Yey!<img src="https://e.com/a.png" alt="A"></p>')).toBe('Yey! ![A](https://e.com/a.png)');
  });
});
