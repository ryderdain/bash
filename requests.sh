#!/usr/bin/env bash
# Adapted from:
# https://www.quora.com/How-do-you-write-a-simple-shell-script-to-send-socket-messages-on-a-Unix-machine

. includes/error.sh

fetch_normalized_response() {
    exec {fd}<>/dev/tcp/${1}/${2:-80}
    printf "GET %s HTTP/1.1\r\nHost: %s\r\nConnection: close\r\n\r\n" "${3:-/}" "${1}" >&$fd
    mapfile response <&$fd
    exec {fd}<>-
    for line in "${response[@]}"
    do
        echo "$(printf '%s' "${line}" | tr -d '[:cntrl:]')"
    done
}

ip_re='([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):?([0-9]{1,5})?'
if [[ "${1}" =~ $ip_re ]]
then
    mapfile -t page < <(fetch_normalized_response ${BASH_REMATCH[1]} ${BASH_REMATCH[2]:-80} ${2:-/})
    for line in "${page[@]}"
    do 
        printf '%s\n' "$line"
    done
else
    which -s dig || error 1 "Requires 'dig' executable"
    dns_re='([a-zA-Z0-9.]+\.[a-zA-Z]{2,5}):?([0-9]{1,5})?'
    if [[ "${1}" =~ $dns_re ]]
    then
        host_ips=($(dig +short ${BASH_REMATCH[1]}))
        [[ ${#host_ips[@]} -ge 1 ]] || error 1 "No domain for ${BASH_REMATCH[1]}"
        mapfile -t page < <(fetch_normalized_response ${BASH_REMATCH[1]} ${BASH_REMATCH[2]:-80} ${2:-/})
        for line in "${page[@]}"
        do
            printf '%s\n' "$line"
        done
    fi 
fi
