#!/bin/sh

# To explicitly error out with a message on stderr.
# Example use in script:
#   true || error 1 "that's not the right value..."
error() {
    ret_code=${1}; shift
    exec >&2
    printf '[%(%F %T)T] '; printf 'ERROR: %s' "${@}"
    exit "${ret_code}"
}
