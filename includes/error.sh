#!/bin/sh

error() {
    ret_code=${1}; shift
    printf '%s [error]: %s' "$(date)" "${@}"
    exit "${ret_code}"
}
