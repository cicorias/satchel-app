// Code-block language hints, applied to the cloned document before extraction (spec §4.5: fenced code takes
// its language from the page). Defuddle reads `data-lang` before any class name, so setting it wins.

/** GitHub (`highlight-source-rust`, `highlight-text-md`) and Sphinx/Pygments (`highlight-console`) wrappers. */
const WRAPPER_LANGUAGE = /^highlight-(?:(?:source|text)-)?([\w+#.-]+)$/;
const NOT_A_LANGUAGE = new Set(['default', 'none', 'notranslate']);

export function annotateCodeLanguages(doc: Document): void {
  for (const wrapper of Array.from(doc.querySelectorAll('[class*="highlight-"]'))) {
    const language = Array.from(wrapper.classList)
      .map((name) => name.match(WRAPPER_LANGUAGE)?.[1]?.toLowerCase())
      .find((name) => name !== undefined && !NOT_A_LANGUAGE.has(name));
    if (!language) continue;
    for (const el of [wrapper, ...Array.from(wrapper.querySelectorAll('pre, code'))]) {
      if (!el.hasAttribute('data-lang')) el.setAttribute('data-lang', language);
    }
  }
  // GitHub wraps a README in <div class="Box md …">, and Defuddle reads a bare "md" class on any ancestor as the
  // language of every code block inside it.
  for (const box of Array.from(doc.querySelectorAll('.Box.md'))) box.classList.remove('md');
}
