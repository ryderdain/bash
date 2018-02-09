#!/bin/sh

split() {
    for word in "$@"
    do
        printf '%s\n' "$word"
    done
}

