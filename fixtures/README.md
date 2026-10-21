# Fixtures

- `pages/<name>/`: golden capture tests (spec §12.4). Each contains `input.html`, `url.txt`, `expected.md`, and `expected-metadata.json`. Phase 1 adds at least 20 of them.
- `model/`: Item JSON contract fixtures, which both TypeScript and Swift must round-trip losslessly (spec §7.1).
