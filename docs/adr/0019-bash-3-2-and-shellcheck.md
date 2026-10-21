# ADR-0019: Shell scripts are bash, bash 3.2-compatible, and ShellCheck-clean

- **Status:** Accepted
- **Amends:** [ADR-0013](0013-tooling-mise-biome-swift-format.md) (adds ShellCheck to the toolchain)
- **Date:** 2026-10-21

## Context

All task logic lives in `scripts/<aspect>/*.sh` (ADR-0013). On macOS, `#!/usr/bin/env bash` resolves to Apple's `/bin/bash` **3.2** unless the user installs a newer bash, and Xcode build phases always get 3.2. A bash 4 idiom has already broken a script once: an empty array expanded under `set -u` is an "unbound variable" error in 3.2, which made `FORCE=1` in `xcodegen.sh` exit silently. The developer's interactive shell is zsh, so we considered writing the scripts in zsh.

## Decision

- Scripts are **bash** (`#!/usr/bin/env bash`, `set -euo pipefail`) and must run on **bash 3.2**. The forbidden constructs and safe idioms are listed in `AGENTS.md` → "Shell scripts".
- **ShellCheck** (pinned in `mise.toml`, configured by `.shellcheckrc`) lints every tracked `*.sh` file and `.githooks/*`.
- ShellCheck can't target a bash version, so `scripts/verify/shell.sh` adds two checks: a grep guard against bash 4+ constructs (an exception needs `# bash3-ok <reason>`), and, on macOS, a `/bin/bash -n` parse with the real 3.2.
- `mise run verify:shell` is part of `mise run verify`. It runs in `ci-web` (Linux) and in `ci-apple` (macOS, where the 3.2 parse check applies).

## Consequences

- ✅ Scripts behave the same in a terminal, in Xcode build phases, on a fresh Mac, and on the Linux CI runner.
- ✅ ShellCheck catches quoting, word-splitting, and unused or unset variable bugs before review.
- ⚠️ Some conveniences are off-limits (associative arrays, `mapfile`, `${v,,}`). For anything that needs real data structures, write a small Node script and call it from bash, as `gen-config` and `render` already do.
- ⚠️ The grep guard is pattern-based. It can miss creative spellings, and it can't catch the empty-array `set -u` behavior. That case relies on the documented idiom and on CI running the scripts on macOS.

## Alternatives considered

- *zsh:* it's the developer's shell, but it isn't guaranteed on Linux CI images, ShellCheck doesn't support it, and it has subtle semantic differences (1-based arrays, no word splitting of unquoted variables).
- *Pin a modern bash through mise:* helps only when invoked through mise. Xcode phases and direct runs would still get 3.2, so the 3.2 discipline would be needed anyway.
- *POSIX `sh` only:* even more restrictive (no arrays, no `pipefail` on older shells), for no benefit on our targets.
