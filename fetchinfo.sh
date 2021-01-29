#!/bin/bash
# Adapted from:
# https://www.quora.com/How-do-you-write-a-simple-shell-script-to-send-socket-messages-on-a-Unix-machine

error() {
    ret_code=${1}; shift
    printf '%s [error]: %s' "$(date)" "${@}"
    exit "${ret_code}"
}

fetch_response() {
    exec 4>&- # in case it's open from previous call
    exec 4<>/dev/tcp/${1}/${2:-80}
    printf "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" "${3:-/}" "${1}" >&4
    mapfile response <&4
    for line in "${response[@]}"
    do
        printf '%s' "${line}"
    done
    exec 4>&-
}

main() {
    ip_re='([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):?([0-9]{1,5})?'
    if [[ "${1}" =~ $ip_re ]]
    then
        fetch_response ${BASH_REMATCH[1]} ${BASH_REMATCH[2]:-80} ${2:-/}
    else
        fetch_response 169.254.169.254 80 /latest/meta-data/${1}
    fi
    printf '\n'
}

main $@
