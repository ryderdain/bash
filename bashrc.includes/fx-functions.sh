#!/usr/bin/env bash

# Supply an FX token for the forex.sh script before adding.

error() {
    ret_code=${1}; shift
    printf '[%(%F %T)T] '
    printf 'ERROR: %s' "${@}"
    exit "${ret_code}"
}

fx() {
    if [[ -n "${1}" ]] && [[ "${1}" != "EUR" ]] ; then error 2 "only EUR is currently supported by your current plan." ; fi
    $HOME/Local/github/bash/forex.sh $FX_TOKEN ${1:-EUR} ${2:-USD}
}

in_usd() {
    printf '%.2f\n' "$(bc -l <<<"${1:-"1.0"} * $(fx 2>/dev/null)")"
}

in_eur() {
    printf '%.2f\n' "$(bc -l <<<"${1:-"1.0"} / $(fx 2>/dev/null)")"
}
