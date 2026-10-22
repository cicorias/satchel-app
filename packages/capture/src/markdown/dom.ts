// DOM helpers used by the converter.
//
// Ported from Defuddle 0.19.4, src/utils.ts and src/utils/dom.ts (commit d4c4bad), https://github.com/kepano/defuddle
// MIT License. Copyright (c) 2025 Steph Ango (@kepano). See THIRD_PARTY_NOTICES.md for the full notice.

const ELEMENT_NODE = 1;
const TEXT_NODE = 3;

export const isElement = (node: Node): node is Element => node.nodeType === ELEMENT_NODE;

export const isTextNode = (node: Node): node is Text => node.nodeType === TEXT_NODE;

/** Whether `el` belongs to `ancestor` directly, not to a table nested in between. */
export function isDirectTableChild(el: Node, ancestor: Node): boolean {
  let parent = el.parentNode;
  while (parent && parent !== ancestor) {
    if (parent.nodeName === 'TABLE') return false;
    parent = parent.parentNode;
  }
  return parent === ancestor;
}
