#!/usr/bin/env bash
# Lint shell scripts (ADR-0019): ShellCheck, a guard against bash 4+ features, and, on macOS, a parse
# check with Apple's /bin/bash 3.2 (what `#!/usr/bin/env bash` resolves to on a stock Mac).
set -euo pipefail
cd "$(dirname "$0")/../.."

scripts=()
while IFS= read -r f; do scripts+=("$f"); done < <(git ls-files '*.sh' '.githooks/*')

shellcheck "${scripts[@]}"

# ShellCheck can't target a bash version, so reject bash 4+ constructs explicitly.
# Allowed exceptions: put "# bash3-ok" at the end of the line, with a reason.
bash4='declare -[gAn]|local -[An]|typeset -A|\bmapfile\b|\breadarray\b|\bcoproc\b|\$\{[A-Za-z_][A-Za-z0-9_]*(,,?|\^\^?)\}|\|&|&>>|\[\[ -v |\bwait -n\b|shopt -s (globstar|lastpipe)|\$\{[A-Za-z_][A-Za-z0-9_]*\[-[0-9]+\]\}|\bEPOCHSECONDS\b|\bEPOCHREALTIME\b|\$\{[A-Za-z_][A-Za-z0-9_]*@[QEPAa]\}' # bash3-ok: the guard's own pattern list
if grep -nE "$bash4" "${scripts[@]}" | grep -v '# bash3-ok'; then
  echo "error: bash 4+ construct found (scripts must run on macOS bash 3.2; see AGENTS.md)" >&2
  exit 1
fi

if [ -x /bin/bash ] && /bin/bash --version | grep -q 'version 3\.'; then
  for f in "${scripts[@]}"; do /bin/bash -n "$f"; done
fi
echo "shell: ${#scripts[@]} scripts OK"
