#!/usr/bin/env bash
#
# ┌─ PULLED-IN EXAMPLE ─ verbatim; do not edit here ─────────────────────────
# │ source   : ryderdain/barzel-cluster @ fd95b5a
# │ path     : gitops/tools/lib/runlib.sh
# │ pulled   : 2026-08-03
# │ shows    : §1.4 the shared harness — end_function, require_tools (extracted, de-project-ified, to includes/runlib.sh)
# └─ edit upstream and re-pull; see examples/README.md ──────────────────────
#
# runlib.sh — shared harness for the "sourceable main() pattern" (CLAUDE.md). It is
# NOT an action script; `source` it from one. It gives every action script the same
# calling surface so an orchestrator (e.g. tools/platform.sh) can sequence complex
# actions legibly for junior operators, while each script still runs standalone.
#
# Contract for a script that sources this:
#   1. Detect whether IT was sourced, BEFORE sourcing this lib (detection must run in
#      the script's own frame):  (return 0 2>/dev/null) && is_sourced=true || is_sourced=false
#   2. source this file: source "<repo>/gitops/tools/lib/runlib.sh"
#   3. Put work in named functions; finish each with: end_function "$?" 'message'
#   4. End the file with a CLI-dispatch block that runs only when NOT sourced:
#        if [[ "$is_sourced" == false ]]; then "${@:-<default_fn>}"; fi
#
# This composes with — does not replace — the repo's emit-commands convention: an
# emit-style action's function still PRINTS commands to stdout (the orchestrator
# pipes them, `bash x.sh | bash`); a generator's function PRINTS data to stdout.
# end_function logs to STDERR so it never pollutes an emitted/generated stdout stream.

# Re-source guard: define the harness once even if several scripts pull it in.
[[ -n "${__RUNLIB_SOURCED:-}" ]] && return 0
__RUNLIB_SOURCED=1

if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required (runlib.sh)\n' >&2
  # Sourced → return; executed directly → exit. (SC2317: the exit is reachable only
  # in the direct-run case, which shellcheck can't see statically.)
  # shellcheck disable=SC2317
  { return 1 2>/dev/null || exit 1; }
fi

# _ts — timestamp for log lines. printf %()T is a bash-4 builtin (no fork); fall
# back to date(1) only if somehow on an older bash (guarded above, but keep it safe).
if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
  _ts() { printf '%(%F %T)T' -1; }
else
  _ts() { date +'%F %T'; }
fi

# end_function <rc> <msg...> — log the outcome of the CALLING function to stderr,
# then either return (so a sourcing orchestrator survives a callee failure and can
# decide what to do) or exit (when the script was run directly). Mirrors the
# ryderdain/bash/tests/destroy-tf-modules.sh end_function semantics.
#   - rc == 0 : log INFO, return 0 (never exits — lets a direct run continue).
#   - rc != 0 : log ERROR; if the script was sourced, `return rc`; else `exit rc`.
# Reads the global `is_sourced` set by the sourcing script (defaults to false).
end_function() {
  local rc="${1:-0}"; shift
  local where="${FUNCNAME[1]:-main}"
  if [[ "$rc" -eq 0 ]]; then
    printf '[%s] INFO  (%s): %s\n' "$(_ts)" "$where" "$*" >&2
    return 0
  fi
  printf '[%s] ERROR (%s): %s\n' "$(_ts)" "$where" "$*" >&2
  [[ -n "${starting_position:-}" ]] && cd "$starting_position" 2>/dev/null || :
  if [[ "${is_sourced:-false}" == true ]]; then
    return "$rc"
  fi
  exit "$rc"
}

# require_tools <tool...> — explicit PATH check (no `set -e` reliance, per CLAUDE.md).
# Returns 1 if any is missing (caller passes the rc to end_function).
require_tools() {
  local tool missing=0
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      printf 'error: %s not found on PATH\n' "$tool" >&2
      missing=1
    fi
  done
  return "$missing"
}

# aws_profile_note — informational: report which credential source AWS calls will use.
# Supports the dual-locus rule (CLAUDE.md): AWS_PROFILE on a laptop, instance-role
# creds on the conductor (no profile). Never fails; just prints to stderr.
aws_profile_note() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    printf 'aws creds : profile %q\n' "$AWS_PROFILE" >&2
  else
    printf 'aws creds : no AWS_PROFILE set — using ambient/instance-role credentials\n' >&2
  fi
}

# emit_k8s_secret <ns> <name> <key=SRC ...> — the SHARED in-cluster-Secret emitter
# for the bootstrap secret-creator scripts (create-cluster-secrets.sh,
# create_sso_secrets.sh). PRINTS a namespaced create-or-update for one Secret; never
# touches the cluster itself (emit-commands convention). SRC is either:
#   - an ENV-VAR NAME  → emitted as "$VAR", so its value expands only in the PIPED
#                        shell, from that shell's inherited env (never in the preview);
#   - '@<expr>'        → the literal shell expression after '@' is emitted verbatim
#                        (e.g. '@${FOO:-$(openssl rand -hex 20)}'), also evaluated in
#                        the piped shell — for a default or an inline-generated value.
# Both forms keep secret material out of the printed text — only $VAR / $(...) literals
# appear. The two sides of `script | bash` are separate processes, so a value reaches
# the piped shell via the caller's inherited env or is generated inline there; a
# runtime `export` in the emitting script would NOT be seen downstream.
# NOTE: pass an '@'-literal argument SINGLE-QUOTED at the call site (and disable SC2016)
# so it survives to here unexpanded.
emit_k8s_secret() {
  local ns="$1" name="$2"; shift 2
  local args="" pair k var
  for pair in "$@"; do
    k="${pair%%=*}"; var="${pair#*=}"
    if [[ "$var" == @* ]]; then
      args+=" --from-literal=${k}=\"${var#@}\""    # literal expr → evaluated in piped shell
    else
      args+=" --from-literal=${k}=\"\$${var}\""     # env var by name → expands in piped shell
    fi
  done
  printf '%s\n' "\
kubectl create namespace ${ns} --dry-run=client -o yaml | kubectl apply -f - && \\
kubectl -n ${ns} create secret generic ${name}${args} \\
  --dry-run=client -o yaml | kubectl apply -f -"
}
