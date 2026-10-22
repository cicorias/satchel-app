// markdown-it-footnote ships no types, and @types/markdown-it-footnote targets markdown-it 14's DefinitelyTyped types,
// while markdown-it 15 ships its own. This is all we use.
declare module 'markdown-it-footnote' {
  import type { MarkdownIt } from 'markdown-it';

  const footnote: (md: MarkdownIt) => void;
  export default footnote;
}
