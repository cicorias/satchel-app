# Architecture Decision Records

| # | Title | Status | File |
|---|---|---|---|
| 0001 | Single repository (monorepo) | Accepted | [0001-monorepo.md](0001-monorepo.md) |
| 0002 | Defuddle for content extraction | Accepted | [0002-defuddle.md](0002-defuddle.md) |
| 0003 | Turndown for HTML → Markdown | Accepted | [0003-turndown.md](0003-turndown.md) |
| 0004 | CloudKit first, behind a provider abstraction | Accepted; amended by 0011; schema-as-file addendum | [0004-cloudkit-first.md](0004-cloudkit-first.md) |
| 0005 | Safari via the shared WXT codebase and Apple's packager | Accepted, pending Spike B addendum; amended by 0011 | [0005-safari-packager.md](0005-safari-packager.md) |
| 0006 | Client-side capture | Accepted | [0006-client-side-capture.md](0006-client-side-capture.md) |
| 0007 | Safari saves through native code | Accepted | [0007-safari-native-saves.md](0007-safari-native-saves.md) |
| 0008 | XcodeGen for the Apple project | Accepted | [0008-xcodegen.md](0008-xcodegen.md) |
| 0009 | Images — references first, stored assets later, Base64 only on export | Accepted | [0009-images.md](0009-images.md) |
| 0010 | Product name and identifiers | Accepted | [0010-name-and-identifiers.md](0010-name-and-identifiers.md) |
| 0011 | Delivery order — iPhone first | Accepted | [0011-delivery-order-iphone-first.md](0011-delivery-order-iphone-first.md) |
| 0012 | Minimum iOS 26 | Accepted | [0012-ios-26-minimum.md](0012-ios-26-minimum.md) |
| 0013 | Tooling — mise, Biome, swift-format, AGENTS.md | Accepted; amended by 0018, 0019 | [0013-tooling-mise-biome-swift-format.md](0013-tooling-mise-biome-swift-format.md) |
| 0014 | Public repository, source-available license, no secrets | Accepted | [0014-public-repo-source-available.md](0014-public-repo-source-available.md) |
| 0015 | CalVer versioning | Accepted | [0015-calver-versioning.md](0015-calver-versioning.md) |
| 0016 | Release, CI, and web hosting | Accepted | [0016-release-ci-and-hosting.md](0016-release-ci-and-hosting.md) |
| 0017 | GRDB + SQLite for the Apple local store | Accepted | [0017-local-store-grdb.md](0017-local-store-grdb.md) |
| 0018 | Work items live in the repo, not GitHub Issues | Accepted | [0018-work-items-in-repo.md](0018-work-items-in-repo.md) |
| 0019 | Shell scripts: bash 3.2-compatible, ShellCheck-clean | Accepted | [0019-bash-3-2-and-shellcheck.md](0019-bash-3-2-and-shellcheck.md) |
| 0020 | Swift runs the TypeScript model in JavaScriptCore | Accepted | [0020-swift-model-logic-in-javascriptcore.md](0020-swift-model-logic-in-javascriptcore.md) |

## Adding or changing an ADR

1. Copy the format of an existing ADR into `NNNN-short-slug.md` using the next number, with Status and Date lines, then add it to the table above.
2. Never silently edit an accepted ADR's decision. If it proves wrong, write a new ADR that supersedes it and explains why.
3. In the old ADR, change only its Status to `Superseded by [ADR-NNNN](...)` (or add an `Amended by` line for partial changes).
4. Spike findings and other verified facts go under an `## Addendum` heading at the end of the relevant ADR, dated.
5. Keep [`../spec.md`](../spec.md) consistent: where a new ADR changes the spec, edit the spec and cite the ADR.
