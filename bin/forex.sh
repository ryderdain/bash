#!/usr/bin/env bash

. $HOME/Local/github/bash/includes/cache_last_exec.sh

# Sign up and get a key from http://fixer.io
FOREX_KEY="${1:-none}" ; shift
[[ "$FOREX_KEY" != 'none' ]] || error 1 "requires a valid key for fixer.io"
base_ccy="${1:-EUR}" ; shift
target_ccy="${1:-USD}" ; shift
cachefile="forex.${base_ccy}.json"

cache "$cachefile" curl -s --get \
    -d "access_key=${FOREX_KEY}" \
    -d "base=${base_ccy}" \
"http://data.fixer.io/api/latest"

fx_rate="$(jq -r '.rates.'"$target_ccy" < "$time_cache/$cachefile")"
fx_date="$(jq -r '.date' < "$time_cache/$cachefile")"

_ts; printf '1.00 %s in %s as of %s:\n' "$base_ccy" "$target_ccy" "$fx_date" >&2 # Send to stderr to exclude in scripts
printf '%s\n' "$fx_rate"
