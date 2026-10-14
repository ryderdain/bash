#!/usr/bin/env bash
# emit-group-cases.sh — backs the claims in doctrine/STYLE.md §1.2 about emitted
# groups that tests/emit-grouping-demo.sh does not already cover: collecting a
# group's output, what a pipe after a group does to shell state, and the
# one-check-where-it-matters pattern.
#
# Read-only check archetype. Each case runs a small emitted stream in a child
# shell and compares what happened with what the doctrine says will happen. It
# prints one line per case and exits non-zero if any claim stops holding.
#
#   bash tests/emit-group-cases.sh        # report
#   bash tests/emit-group-cases.sh -q     # exit code only
#
# The streams below are single-quoted on purpose: they are emitted text, and
# only the child shell may expand them (§1.3).
# shellcheck disable=SC2016

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

"$quiet" || printf 'emitted-group cases (bash %s)\n\n' "$BASH_VERSION"

# The bespoke log helper the doctrine shows. A stream defines it once, at the
# top, only when it uses it.
log_fn='log() { while IFS= read -r line; do printf "%s | %s\n" "$1" "$line"; done; }'

# The doctrine's error function, read from the real include so the test checks
# the definition a stream would actually carry.
here="${BASH_SOURCE[0]%/*}"
error_fn="$(<"$here/../includes/error.sh")" || { printf 'error: cannot read includes/error.sh\n' >&2; exit 1; }

# 1. One redirection after the closing brace collects the output of EVERY
#    command in the group, stdout and stderr alike. This is why a block can be
#    labelled as a whole instead of piping each command separately.
stream="$log_fn"'
{
  printf "made\n"
  printf "warned\n" >&2
} 2>&1 | log ecr'
got="$(bash -c "$stream" | tr '\n' ';')"
report 'one pipe after the group labels the output of all its commands' \
  'ecr | made;ecr | warned;' "$got"

# 2. A group on the LEFT of a pipe runs in a subshell, so what it sets does not
#    reach the next group. The doctrine's answer is that a group is an anonymous
#    function: it should not hand state to its neighbour anyway. If this case
#    ever fails, the advice to keep groups self-contained must be re-checked.
stream="$log_fn"'
{ v=set_inside; } 2>&1 | log first
printf "%s" "${v:-unset}"'
got="$(bash -c "$stream")"
report 'a piped group does not leak variables to the next group' 'unset' "$got"

# 3. Without a pipe, the same group runs in the consuming shell and its state
#    does persist. Shown for contrast with case 2, so a reader sees that the pipe
#    is what changes the behaviour, not the braces.
stream='{ v=set_inside; }
printf "%s" "${v:-unset}"'
got="$(bash -c "$stream")"
report 'an unpiped group keeps its variables (contrast with case 2)' 'set_inside' "$got"

# 4. The one-check pattern: where running the block again would hurt, a check
#    on the dangerous step stops the WHOLE stream before the destructive command
#    and says, in words, what state was left. Here the "dump" fails, so the
#    "drop" must never run. The reserved code 3 tells the driver the stop was
#    deliberate.
stream="$error_fn"'
{
  false || error 3 "no dump; schema NOT dropped — safe to run again"
  printf "dropped"
}
printf " later-group-ran"'
got="$(bash -c "$stream" 2>/dev/null; printf 'rc=%s' "$?")"
report 'a failed check stops the destructive step and every later group' 'rc=3' "$got"

# 5. The same check tells the operator what happened, on stderr. (The line
#    starts with a timestamp, which is removed before the comparison.)
got="$(bash -c "$stream" 2>&1 >/dev/null)"
got="${got#\[*\] }"
report 'the operator sees why it stopped' \
  'ERROR: no dump; schema NOT dropped — safe to run again' "$got"

# 6. Where no check is needed, a failure inside a group does NOT stop the
#    group: the next command runs and its own failure shows in the log. This is
#    why a check on every command is redundant for dependent steps.
stream="$log_fn"'
{
  ls /no/such/repo
  ls /no/such/repo/policy
} 2>&1 | log ecr'
got="$(bash -c "$stream" | grep -c '^ecr | ')"
report 'without a check, both dependent failures appear in the log' '2' "$got"

# 7. The trap the "never pipe a checked group" rule exists for: the same check
#    inside a group that IS piped to log stops that group, but its exit only ends
#    the pipe's subshell. Later groups still run and the stream exits 0. If this
#    case ever fails, bash changed and the rule can be relaxed.
stream="$log_fn"$'\n'"$error_fn"'
{
  false || error 3 "no dump"
  printf "dropped\n"
} 2>&1 | log db
printf "later-group-ran"'
got="$(bash -c "$stream" 2>/dev/null | tail -1; printf ' rc=%s' "${PIPESTATUS[0]}")"
report 'a check inside a PIPED group does not stop later groups (why checked groups stay bare)' \
  'later-group-ran rc=0' "$got"

"$quiet" || printf '\n%d case(s), %d failure(s)\n' "$case_num" "$failures"
(( failures == 0 ))
