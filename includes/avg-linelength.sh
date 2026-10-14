#!/usr/bin/env bash

counts="$(mktemp)"
trap "rm -v \"$counts\"" 0 1 2 3 9 15

cat "${1:-/dev/stdin}" | while read -r line
do
    printf '%s\n' "${#line}" >> "$counts" 
done

agg=($(<"$counts"))
sum="$(printf '%s' "${agg[@]/%/+}0" | bc)"
avg="$(printf '(%s / %f)' "$sum" "${#agg[@]}" | bc -l)"

printf 'Average line length for %s: %.5f\n' "$1" "$avg"
