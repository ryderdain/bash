#!/usr/bin/env bash
# emit-grouping-demo.sh — why emitted command streams are grouped in `{ …; }` rather
# than `&&`-chained, demonstrated rather than asserted. Backs doctrine/STYLE.md §1.2.
#
# Read-only check/generator archetype: runs its cases directly, prints a report to
# stdout, exits non-zero if any case does not behave as the doctrine claims. So this is
# also a standing check on a standing claim — if a future bash changes one of these
# semantics, this fails instead of the doctrine quietly becoming wrong.
#
#   bash tests/emit-grouping-demo.sh          # report
#   bash tests/emit-grouping-demo.sh -q       # exit code only
#
# No `set -e`: every case's outcome is captured and compared explicitly, which is the
# entire point of the file.

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required\n' >&2
  exit 1
fi

quiet=false
[[ "${1:-}" == "-q" ]] && quiet=true

failures=0
case_num=0

# report <claim> <expected> <actual> — compare and record. All output to stdout; this
# script IS the report, so stdout is where it belongs.
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
  return 1
}

"$quiet" || printf 'emitted-stream grouping semantics (bash %s)\n\n' "$BASH_VERSION"

# ---------------------------------------------------------------------------
# 1. A brace group runs in the CONSUMING shell, so state set in one group is
#    visible to the next. This is the property `( … )` does not have, and the
#    reason grouped emission composes across separately-emitted steps.
# ---------------------------------------------------------------------------
got="$(printf '%s\n' \
  '{ demo_var=set_in_group_one; }' \
  '{ printf "%s" "${demo_var:-UNSET}"; }' | bash)"
report 'brace group shares the consuming shell (state crosses groups)' 'set_in_group_one' "$got"

got="$(printf '%s\n' \
  '( demo_var=set_in_subshell; )' \
  '{ printf "%s" "${demo_var:-UNSET}"; }' | bash)"
report 'subshell group does NOT share it' 'UNSET' "$got"

# ---------------------------------------------------------------------------
# 2. A group's exit status is its LAST command's. It does not fail fast — this
#    is the property `&&`-chaining had and grouping gives up, and why the
#    doctrine requires explicit guards on failures that matter.
# ---------------------------------------------------------------------------
printf '%s\n' '{ false; printf "kept-going "; true; }' | bash >/dev/null 2>&1
report 'group exit status is the last command'"'"'s, not the first failure' '0' "$?"

got="$(printf '%s\n' '{ false; printf "kept-going"; }' | bash 2>/dev/null)"
report 'a failed command does not stop the rest of its group' 'kept-going' "$got"

# ---------------------------------------------------------------------------
# 3. An explicit guard with `exit` DOES abort the whole piped stream — the
#    supported way to get fail-fast where a failure genuinely matters.
# ---------------------------------------------------------------------------
got="$(printf '%s\n' \
  '{ false || { printf "guarded"; exit 3; }; printf "unreachable"; }' \
  '{ printf "later-group"; }' | bash 2>/dev/null)"
report 'a guard that exits aborts the remaining stream' 'guarded' "$got"

printf '%s\n' \
  '{ false || exit 3; }' \
  '{ printf "later-group"; }' | bash >/dev/null 2>&1
report 'and the guard'"'"'s exit code reaches the caller' '3' "$?"

# ---------------------------------------------------------------------------
# 4. A truncated stream executes NOTHING from an unclosed group: the consuming
#    shell must parse the whole group before running any of it. Bare commands
#    half-execute instead. This is grouping's safety property for a generator
#    that dies mid-emit, or a stream cut over the wire.
# ---------------------------------------------------------------------------
got="$(printf '{\nprintf "step-a"\nprintf "step-b"\n' | bash 2>/dev/null)"
report 'truncated brace group executes nothing' '' "$got"

got="$(printf 'printf "step-a"\nprintf "step-b"\n' | head -c 16 | bash 2>/dev/null)"
report 'truncated BARE commands half-execute (the hazard grouping removes)' 'step-a' "$got"

# ---------------------------------------------------------------------------
# 5. `&&`-chaining does not survive composition. When an orchestrator
#    concatenates two emitters, a chain that failed in the first does not stop
#    the second, and the stream still exits 0. The fail-fast guarantee is
#    absent exactly where the doctrine's orchestrator pattern needs it.
# ---------------------------------------------------------------------------
emitter_a() { printf 'false && \\\n'; printf 'printf "a2"\n'; }
emitter_b() { printf 'printf "b1"\n'; }

got="$({ emitter_a; emitter_b; } | bash 2>/dev/null)"
report 'a failed && chain does not stop a later concatenated emitter' 'b1' "$got"

{ emitter_a; emitter_b; } | bash >/dev/null 2>&1
report 'and the concatenated stream still reports success' '0' "$?"

# ---------------------------------------------------------------------------
if (( failures )); then
  printf '\n%d of %d cases did not behave as doctrine/STYLE.md §1.2 claims.\n' \
    "$failures" "$case_num" >&2
  exit 1
fi
"$quiet" || printf '\nall %d cases behave as doctrine/STYLE.md §1.2 claims.\n' "$case_num"
exit 0
