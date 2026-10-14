#!/usr/bin/env bash

# To explicitly error out with a message on stderr.
# Example use in script:
#   true || error 1 "that's not the right value..."
#
# In an emitted stream (doctrine/STYLE.md §1.2), print this definition at the
# top of the stream and stop deliberately with the reserved code 3 (§1.11):
#   pg_dump ... || error 3 "no dump; schema NOT dropped — safe to run again"
# Bash, not POSIX sh: printf '%(…)T' is a bash builtin feature.
error() {
    ret_code=${1}; shift
    exec >&2
    TZ=UTC printf '[%(%Y-%m-%dT%H:%M:%SZ)T] ' -1; printf 'ERROR: %s\n' "$*"
    exit "${ret_code}"
}
