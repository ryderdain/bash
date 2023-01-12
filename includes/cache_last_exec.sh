#!/usr/bin/env bash

time_cache="$HOME/.cache/touchstones"
mkdir -p "$time_cache" 2>/dev/null

_ts() {
    printf '[%(%F %T)T] ' "-1" >&2
}

error() {
    ret_code=${1}; shift
    _ts; printf 'ERROR: %s' "${@}" >&2
    exit "${ret_code}"
}

cache() {
    # Name of file required 
    [[ -n "$1" ]] || error 1 "$0 requires a filename to cache"
    cached_file="$time_cache/$1" ; shift
    touchstone="${cached_file}.touchstone"
    touch -d `date -v -1d +%Y-%m-%dT%H:%M:%S` "$touchstone"
    
    # Exec string if touchstone older than 24 hours
    if [[ ! -r "$cached_file" ]] || [[ "$cached_file" -ot "$touchstone" ]]
    then
        eval "$*" > "$cached_file"
        _ts; printf 'refreshed cache at %s\n' "$(stat -f '%Sm' "$cached_file")" >&2
    else
        _ts; printf 'cache last refreshed at %s\n' "$(stat -f '%Sm' "$cached_file")" >&2
        return 127 # failed to exec
    fi
    return 0
}
