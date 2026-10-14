#!/usr/bin/env bash
# env-definition-cases.sh — backs doctrine/STYLE.md §1.12: how an environment
# definition file and the operator's exported variables combine.
#
# Read-only check archetype. It writes a two-line environment definition to a
# temporary directory, loads it with load_env_definition from
# includes/runlib.sh in a child shell, and checks the result. It prints one line
# per case and exits non-zero if any claim stops holding.
#
#   bash tests/env-definition-cases.sh        # report
#   bash tests/env-definition-cases.sh -q     # exit code only
#
# The child-shell scripts are single-quoted on purpose: they must expand their
# own variables, not this script's.
# shellcheck disable=SC2016

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

here="${BASH_SOURCE[0]%/*}"
runlib="$here/../includes/runlib.sh"

quiet=false
[[ "${1:-}" == "-q" ]] && quiet=true

failures=0
case_num=0
scratch="$(mktemp -d)" || { printf 'error: mktemp failed\n' >&2; exit 1; }

report() {
  local claim="$1" expected="$2" actual="$3"
  case_num=$(( case_num + 1 ))
  if [[ "$expected" == "$actual" ]]; then
    "$quiet" || printf '  ok %d — %s\n' "$case_num" "$claim"
    return 0
  fi
  failures=$(( failures + 1 ))
  printf 'FAIL %d — %s\n      expected: %s\n      actual:   %s\n' \
    "$case_num" "$claim" "$expected" "$actual" >&2
}

"$quiet" || printf 'environment-definition cases (bash %s)\n\n' "$BASH_VERSION"

# The definition under test: two plain NAME=value lines, as §1.12 requires.
defn="$scratch/demo.env"
printf 'DEMO_SUBSTRATE=k3d\nDEMO_REGISTRY=registry.localhost:5000\n' > "$defn"

# 1. The file holds defaults; a value the operator exported wins. Here the
#    operator exports DEMO_SUBSTRATE=aws for a one-off test and leaves
#    DEMO_REGISTRY alone, so the registry comes from the file.
got="$(DEMO_SUBSTRATE=aws bash -c '
  source "$1"; load_env_definition "$2" 2>/dev/null
  printf "%s %s" "$DEMO_SUBSTRATE" "$DEMO_REGISTRY"' _ "$runlib" "$defn")"
report 'an exported value wins; an unset name takes the file default' \
  'aws registry.localhost:5000' "$got"

# 2. The override is never silent: the operator is told, on stderr, which value
#    replaced which default. That line is what keeps a one-off test on record.
got="$(DEMO_SUBSTRATE=aws bash -c '
  source "$1"; load_env_definition "$2" 2>&1 >/dev/null' _ "$runlib" "$defn")"
report 'the override is announced on stderr' \
  "warning: exported DEMO_SUBSTRATE=aws overrides the default k3d from $defn" "$got"

# 3. Every name in the file is exported, so the commands a driver runs (child
#    processes) see the values, not only the shell that loaded the file.
got="$(bash -c '
  source "$1"; load_env_definition "$2" 2>/dev/null
  bash -c "printf %s \"\$DEMO_REGISTRY\""' _ "$runlib" "$defn")"
report 'child processes see the values' 'registry.localhost:5000' "$got"

rm -rf -- "$scratch"

"$quiet" || printf '\n%d case(s), %d failure(s)\n' "$case_num" "$failures"
(( failures == 0 ))
