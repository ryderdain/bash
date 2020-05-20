#!/usr/bin/env bash
# Adapted from:
# https://www.quora.com/How-do-you-write-a-simple-shell-script-to-send-socket-messages-on-a-Unix-machine

. includes/error.sh

ip_re='([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}):?([0-9]{1,5})?'
if [[ "${1}" =~ $ip_re ]]
then
    printf '===== REQUEST START =====\n'
    exec 3<>/dev/tcp/${BASH_REMATCH[1]}/${BASH_REMATCH[2]:-80}
    printf "GET ${2:-/} HTTP/1.1\r\nHost: ${BASH_REMATCH[1]}\r\nConnection: close\r\n\r\n" >&3
    cat <&3
    printf '\n===== REQUEST END =====\n'
    exec 3<>-
else
    which -s dig || error 1 "Requires 'dig' executable"
    dns_re='([a-zA-Z0-9.]+\.[a-zA-Z]{2,5}):?([0-9]{1,5})?'
    if [[ "${1}" =~ $dns_re ]]
    then
        host_ips=($(dig +short ${BASH_REMATCH[1]}))
        [[ ${#host_ips[@]} -ge 1 ]] || error 1 "No domain for ${BASH_REMATCH[1]}"
        printf '===== REQUEST START =====\n'
        exec 3<>/dev/tcp/${host_ips[0]}/${BASH_REMATCH[2]:-80}
        printf "GET ${2:-/} HTTP/1.1\r\nHost: ${BASH_REMATCH[1]}\r\nConnection: close\r\n\r\n" >&3
        cat <&3
        printf '\n===== REQUEST END =====\n'
        exec 3<>-
    fi 
    printf 'BASH_REMATCH returned "%s"\n' "${BASH_REMATCH[*]}"
fi
