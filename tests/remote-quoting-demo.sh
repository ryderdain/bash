#!/usr/bin/env bash
# remote-quoting-demo.sh — the §1.8 claims about remote execution, demonstrated
# locally. `ssh host "inline cmd"` hands the remote shell a STRING to re-parse;
# `bash -c "$string"` does the identical thing, so it stands in for the remote
# side without needing a host. `gen.sh | ssh host bash` feeds the remote shell
# STDIN; `... | bash` stands in for that. Backs doctrine/STYLE.md §1.8.
#
# Read-only check archetype: runs each case, reports to stdout, exits non-zero
# if the shell ever stops behaving as the doctrine claims.
#
#   bash tests/remote-quoting-demo.sh        # report
#   bash tests/remote-quoting-demo.sh -q     # exit code only

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

"$quiet" || printf 'remote-execution quoting semantics (bash %s)\n\n' "$BASH_VERSION"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
printf 'contents\n' > "${workdir}/my file.txt"

# 1. The inline form re-parses. A correctly-quoted local variable holding a
#    path with a space is split by the SECOND parse: the "remote" shell sees
#    two words. This is the double-parse — the local quoting was not wrong,
#    it just only survived one shell.
f="${workdir}/my file.txt"
got="$(bash -c "cat $f" 2>/dev/null)"
report 'inline form: the second parse splits a spaced path (cat fails)' '' "$got"

# 2. "Fixing" it means quoting FOR THE SECOND PARSE — escaping a string you
#    never see run, which is the quoting hell the rule exists to avoid.
got="$(bash -c "cat \"$f\"" 2>/dev/null)"
report 'inline form works only when quoted for the remote parse' 'contents' "$got"

# 3. The stdin form is parsed once. The same command, well-quoted in the
#    emitted text, arrives byte-identical and just works.
got="$(printf 'cat "%s"\n' "$f" | bash 2>/dev/null)"
report 'stdin form: parsed once, ordinary quoting suffices' 'contents' "$got"

# 4. The inline form resolves values INTO the transmitted string. What crosses
#    the wire (and lands in the remote argv, visible to ps) contains the value.
secret='hunter2'
inline_string="curl -H 'Authorization: $secret' https://example.invalid"
[[ "$inline_string" == *hunter2* ]]
report 'inline form: the transmitted string contains the resolved secret' '0' "$?"

# 5. An emitted stream carries the NAME; the value never appears in the text.
#    Expansion happens only in the consuming shell, from its own environment
#    (§1.3 — same mechanism, applied across the wire).
emitted="$(printf '%s\n' 'curl -H "Authorization: $secret" https://example.invalid')"
[[ "$emitted" != *hunter2* ]]
report 'emitted stream: only the reference crosses; no value in the text' '0' "$?"

if (( failures )); then
  printf '\n%d of %d cases did not behave as doctrine/STYLE.md §1.8 claims.\n' \
    "$failures" "$case_num" >&2
  exit 1
fi
"$quiet" || printf '\nall %d cases behave as doctrine/STYLE.md §1.8 claims.\n' "$case_num"
exit 0
