#!/usr/bin/env bash
# set-e-cases.sh — the four places skill rule 2 claims `set -e` does not fire,
# demonstrated rather than asserted. Backs doctrine/STYLE.md §1.1.
#
# Read-only check archetype: runs each case in a child shell, reports to stdout,
# exits non-zero if bash ever stops behaving as the doctrine claims.
#
#   bash tests/set-e-cases.sh        # report
#   bash tests/set-e-cases.sh -q     # exit code only
#
# See also set-e-test.sh / set-e-test-funcs.sh (the older single-scenario demo)
# and tests/emit-grouping-demo.sh for the same pattern applied to §1.2.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

quiet=false
[[ "${1:-}" == "-q" ]] && quiet=true

failures=0
case_num=0

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

"$quiet" || printf 'set -e non-firing cases (bash %s)\n\n' "$BASH_VERSION"

# 0. Baseline: set -e does abort on a bare failing command. If this ever fails,
#    the four cases below prove nothing.
got="$(bash -c 'set -e; false; printf reached' 2>/dev/null)"
report 'baseline: a bare failing command DOES abort' '' "$got"

# 1. Command lists: a failure anywhere but the final position of && / || is exempt.
got="$(bash -c 'set -e; false && true; printf reached' 2>/dev/null)"
report 'command list: `false && true` does not abort' 'reached' "$got"

# 2. Conditional context: a failing command tested by if/while/! is exempt (that
#    is what testing means), so nothing in a condition ever fires set -e.
got="$(bash -c 'set -e; if false; then :; fi; printf reached' 2>/dev/null)"
report 'condition: a failure under `if` does not abort' 'reached' "$got"

# 3. Functions called from a condition: set -e is suspended for the ENTIRE body —
#    including bare failures that would abort anywhere else (case 0).
got="$(bash -c 'set -e; fn() { false; printf survived-; }; if fn; then :; fi; printf reached' 2>/dev/null)"
report 'function in a condition: its whole body loses set -e' 'survived-reached' "$got"

# 4. `local x=$(false)`: local is a command with its own (zero) exit status, which
#    replaces the substitution's failure. rc masked, nothing fires, $? is 0.
got="$(bash -c 'set -e; fn() { local x=$(false); printf "rc=$?"; }; fn' 2>/dev/null)"
report '`local x=$(false)`: local masks the failure (rc=0)' 'rc=0' "$got"

if (( failures )); then
  printf '\n%d of %d cases did not behave as doctrine/STYLE.md §1.1 claims.\n' \
    "$failures" "$case_num" >&2
  exit 1
fi
"$quiet" || printf '\nall %d cases behave as doctrine/STYLE.md §1.1 claims.\n' "$case_num"
exit 0
