#!/usr/bin/env bash

error() {
    ret_code=${1}; shift
    printf '%s [ERROR]: %s' "$(date)" "${@}"
    return "${ret_code}"
}

testfunc() {
    errout="$(mktemp)"
    for ((i=0;i<10;i++))
    do
        ssh-keyscan -T1 example.com 2>"$errout"
    done
    cat $errout
    rm -v $errout
}
