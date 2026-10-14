#!/usr/bin/env bash
# runlib.sh — the shared harness for the sourceable main() pattern (doctrine §1.4).
# It is NOT an action script; `source` it from one.
#
# Contract for a script that sources this:
#
#   1. Detect whether IT was sourced, BEFORE sourcing this lib. Detection must run in
#      the script's own frame — a helper function cannot do it for you:
#          (return 0 2>/dev/null) && is_sourced=true || is_sourced=false
#   2. source this file:
#          source "<path>/includes/runlib.sh"
#   3. Put all work in named functions; finish each with:
#          end_function "$?" 'what just happened'
#   4. End the file with a CLI-dispatch block that runs only when NOT sourced:
#          if [[ "$is_sourced" == false ]]; then
#            if (( $# )); then "$@"; else default_action; fi
#          fi
#
# This COMPOSES WITH — does not replace — the emit-commands convention (§1.2): an
# emit-style action's function still PRINTS commands to stdout for the caller to pipe
# (`bash x.sh | bash`); a generator's function PRINTS data to stdout. Everything this
# harness logs goes to STDERR, so it never pollutes that stream.
#
# See also includes/error.sh for the simpler `error <rc> <msg>` bail-out, which suits
# scripts too small to want the sourced/direct distinction.

# Re-source guard: define the harness once even if several scripts pull it in.
[[ -n "${__RUNLIB_SOURCED:-}" ]] && return 0
__RUNLIB_SOURCED=1

# §1.1: mandate a minimum bash version and enforce it, rather than writing for the
# lowest common denominator. printf '%()T', associative arrays, and mapfile all need 4.
if (( BASH_VERSINFO[0] < 4 )); then
  printf 'error: bash >= 4 required (runlib.sh)\n' >&2
  # Sourced → return; executed directly → exit. (SC2317: the exit is reachable only
  # in the direct-run case, which shellcheck cannot see statically.)
  # shellcheck disable=SC2317
  { return 1 2>/dev/null || exit 1; }
fi

# _ts — timestamp for log lines: UTC, ISO 8601, with Z. One format on every
# host and in every container, so lines from different loci sort and join.
# printf %()T is a bash-4 builtin, so no fork per line; TZ=UTC applies to
# this one call.
_ts() { TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1; }

# end_function <rc> <msg...> — log the outcome of the CALLING function to stderr, then
# either return or exit:
#
#   rc == 0 : log INFO and return 0. Never exits — a clean step must let a direct run
#             continue to the next one.
#   rc != 0 : log ERROR, then RETURN if the script was sourced and EXIT if it was run
#             directly. That asymmetry is the whole point: a sourcing orchestrator
#             survives a callee's failure and decides what to do about it, while a
#             standalone run still fails hard and loudly.
#
# Reads the global `is_sourced` the calling script set in step 1 (defaults to false,
# i.e. fail hard, which is the safe assumption if a caller forgot the detection line).
# Restores `starting_position` if the script set one before cd'ing around.
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

# require_tools <tool...> — explicit PATH check for every tool the caller depends on.
# Reports ALL missing tools, not just the first, so one run tells the operator
# everything they need to install. Returns 1 if any is missing; the caller passes that
# return code to end_function rather than relying on `set -e` (§1.1, BashFAQ/105).
#
#   require_tools aws jq kubectl || end_function "$?" 'missing prerequisites'
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

# emit_to <content> [target] — the §1.5 convention in one call: stdout is canonical,
# the file is an argument. ALWAYS prints the content to stdout, so behaviour is
# identical whether or not a file was asked for; when a target path is given it ALSO
# writes there, backing up any existing file first and announcing the path on STDERR
# so the piped payload stays clean.
#
#   emit_to "$rendered_manifest"                    # pipe it: | kubectl apply -f -
#   emit_to "$rendered_manifest" ./cluster.yaml     # …and keep a copy
emit_to() {
  local content="$1" target="${2:-}"

  printf '%s\n' "$content"
  [[ -n "$target" ]] || return 0

  if [[ -f "$target" ]]; then
    local backup
    backup="${target}.bak.$(TZ=UTC printf '%(%Y%m%dT%H%M%SZ)T' -1)"
    if ! cp -p -- "$target" "$backup"; then
      printf 'error: could not back up %s; refusing to overwrite\n' "$target" >&2
      return 1
    fi
  fi

  if ! printf '%s\n' "$content" > "$target"; then
    printf 'error: could not write %s\n' "$target" >&2
    return 1
  fi

  printf 'wrote → %s\n' "$target" >&2
}

# --- §1.12 environment definitions ---------------------------------------------------
#
# load_env_definition <file> — source a committed environment definition (a plain list
# of NAME=value lines) so that a value the operator already EXPORTED wins over the
# file's default. Each override is announced on stderr; every name in the file is
# exported. The names are kept in ENV_DEFINITION_NAMES so a driver can record the
# resolved values (env_definition_record). Environment definitions hold no secrets.
#
#   load_env_definition env/local.env || end_function "$?" 'environment definition'
load_env_definition() {
  local file="$1" line name
  local -A preset=()
  ENV_DEFINITION_NAMES=()

  if [[ ! -r "$file" ]]; then
    printf 'error: cannot read environment definition %s\n' "$file" >&2
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)= ]] || continue
    name="${BASH_REMATCH[1]}"
    ENV_DEFINITION_NAMES+=("$name")
    [[ -n "${!name+x}" ]] && preset["$name"]="${!name}"
  done < "$file"

  # shellcheck source=/dev/null
  if ! source "$file"; then
    printf 'error: could not source environment definition %s\n' "$file" >&2
    return 1
  fi

  for name in "${ENV_DEFINITION_NAMES[@]}"; do
    if [[ -n "${preset[$name]+x}" ]]; then
      if [[ "${preset[$name]}" != "${!name}" ]]; then
        printf 'warning: exported %s=%s overrides the default %s from %s\n' \
          "$name" "${preset[$name]}" "${!name}" "$file" >&2
      fi
      printf -v "$name" '%s' "${preset[$name]}"
    fi
    export "${name?}"
  done
}

# env_definition_record — print the resolved values as comment lines, for the top of a
# run-log (§1.11), so a one-off override is always on record.
env_definition_record() {
  local name
  for name in "${ENV_DEFINITION_NAMES[@]}"; do
    printf '# %s=%s\n' "$name" "${!name}"
  done
}
