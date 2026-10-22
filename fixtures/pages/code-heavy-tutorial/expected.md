---
id: u_bca7d7c39f723cbdcf3abe302817097b
type: page
title: "Writing a tiny Markdown linter in three languages"
url: https://notes.byteorchard.example/posts/writing-a-tiny-markdown-linter/
canonical: https://notes.byteorchard.example/posts/writing-a-tiny-markdown-linter/
site: "Byte Orchard"
author: "Ilse Marchetti"
published: 2026-06-22T01:45:00.000Z
saved: 2026-10-22T12:00:00.000Z
updated: 2026-10-22T12:00:00.000Z
description: "Rules, a tokenizer, and test fixtures: the same small linter written in Python, TypeScript, and Go."
image: https://notes.byteorchard.example/og/tiny-linter.png
tags: []
engine: defuddle@0.19.4 + turndown@7.2.4
---

# Writing a tiny Markdown linter in three languages

I wanted a linter that checks two things in my notes: that headings never skip a level, and that every fenced code block names its language. Existing tools do far more than that, so I wrote my own, and then, because I was curious how the code would feel in each language, I wrote it again twice.

The rules are deliberately dumb. A line that starts with one or more `#` characters followed by a space is a heading. A line that starts with three backticks opens or closes a fence. Everything else is ignored, including `*emphasis*`, `__strong__`, and identifiers like `max_heading_jump` or `**kwargs` that would trip up a naive regex.

## Python

The Python version is the reference implementation. It reads the file once and yields problems as it goes:

```python
import re
from typing import Iterator

HEADING = re.compile(r"^(#{1,6}) ")

def lint(lines: list[str]) -> Iterator[tuple[int, str]]:
    level, in_fence = 0, False
    for number, line in enumerate(lines, start=1):
        if line.startswith("```"):
            if not in_fence and line.strip() == "```":
                yield number, "fence without a language"
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if match := HEADING.match(line):
            new = len(match.group(1))
            if new > level + 1:
                yield number, f"heading jumps from h{level} to h{new}"
            level = new
```

## TypeScript

The TypeScript version is nearly a line-for-line port. The only real change is that it returns an array, because that is what the editor plugin wants:

```ts
const HEADING = /^(#{1,6}) /;

export function lint(lines: string[]): Array<[number, string]> {
  const problems: Array<[number, string]> = [];
  let level = 0;
  let inFence = false;
  lines.forEach((line, i) => {
    if (line.startsWith("```")) {
      if (!inFence && line.trim() === "```") problems.push([i + 1, "fence without a language"]);
      inFence = !inFence;
      return;
    }
    const match = inFence ? null : HEADING.exec(line);
    if (match && match[1].length > level + 1) problems.push([i + 1, `heading jumps from h${level} to h${match[1].length}`]);
    if (match) level = match[1].length;
  });
  return problems;
}
```

## Go

Go made me be explicit about errors when reading the file, which the other two quietly skip:

```go
func Lint(r io.Reader) ([]Problem, error) {
    scanner := bufio.NewScanner(r)
    var problems []Problem
    for n := 1; scanner.Scan(); n++ {
        problems = check(problems, n, scanner.Text())
    }
    return problems, scanner.Err()
}
```

## Test fixtures

All three versions share the same fixture file. It contains a fence with no language, which is the case the linter must flag:

````markdown
# Notes

### Skipped a level

```
plain fence, no language
```

```sh
echo "this one is fine"
```
````

Run the whole suite with `make test`, or a single language with `make test LANG=go`. Expected output is one line per problem, in the form `path:line: message`.

The Python version is the shortest, the Go version is the fastest by a wide margin on large files, and the TypeScript version is the one I actually use, because it runs inside my editor. None of them is longer than eighty lines.
