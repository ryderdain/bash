#!/bin/sh


## Pretty Colors!
#   NOTE: 'E' def left at end for when $(cat) used on terminal
RED='[31m'; GREEN='[32m'; YELLOW='[33m'; BLUE='[34m'; MAGENTA='[35m'; CYAN='[36m';
BOLDFACE='[1m';
UNDERLINE='[4m';
ENDFMT='[0m';


## Usage
DESCRIPTION="
Pretty-prints useful info about the SSL certificate. Can fetch via DNS
entry or checks a file. Can pass a CA root file as a second argument.
"
USAGE="
Usage:
    $0 <fqdn|file> [ <cafile> ]

"

## Compatibility
if [ "$(uname)" = "FreeBSD" ]
then
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -jf "
    MD5=/sbin/md5
elif [ "$(uname)" = "Darwin" ]
then
    ## WARNING: older Bourne Shell is nonexistent on Darwin
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -jf "
    MD5=/sbin/md5
elif [ "$(uname)" = "Linux" ]
then
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -d "
    MD5=/usr/bin/md5sum
fi


## Utilities
getip() {
    host -t A -4 "${1}" | grep -m1 -oE '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
    return $?
} 
getsuf() {
    head /dev/random | $MD5 | cut -c1-8
}
error() {
    ret_code=${1}; shift
    printf "%s [error]: %s" "$(date)" "${@}"
    printf "%s" "$USAGE"
    exit ${ret_code}
}

## Checks
check_expiry() {
    sslEndDate="$(openssl x509 -noout -enddate -in ${1})"
    sslEnd="$($STR2DATE 'notAfter=%b %d %H:%M:%S %Y %Z' "${sslEndDate}" +%s)"
    [ "$sslEnd" -gt "$(date -v +${2:-0}d +%s)" ]; return $?
}
check_start() {
    sslStartDate="$(openssl x509 -noout -startdate -in ${1})"
    sslStart="$($STR2DATE 'notBefore=%b %d %H:%M:%S %Y %Z' "${sslStartDate}" +%s)"
    [ "$sslStart" -lt "$(date -v +${2:-0}d +%s)" ]; return ${?}
}

## Printers
print_expiry() {
    CERT=${1}
    sslEndDate="$(openssl x509 -noout -enddate -in "${CERT}" | sed -e 's/\(.*\)=\(.*\)/\2/')"
    if ! (check_expiry ${CERT} 0)
    then 
        printf 'EXPIRED: %s\n' "${BOLDFACE}${RED}$sslEndDate${ENDFMT}"
    elif ! (check_expiry ${CERT} 30)
    then
        printf 'Expires Soon: %s\n' "${BOLDFACE}${YELLOW}$sslEndDate${ENDFMT}"
    else
        printf 'Expires: %s\n' "${GREEN}$sslEndDate${ENDFMT}"
    fi
}
fmt_altnames() {
    count=0
    for an in "$@"
    do
        printf '%02d: %s\n' "$count" "$an"
        count="$((count+1))"
    done
}
print_altnames() {
    printf '\n%s\n' "___ Subject Alternative Names ___"
    fmt_altnames "$(openssl x509 -noout -text -in ${1} | grep -oE 'DNS:.*[^,$ ]' | sed -e 's/,//g;s/DNS:\([^ $]*\)/\1 /g')"
}
print_subject() {
    eval "$(openssl x509 -noout -subject -in ${1} | sed -e 's/[^/]*\/\([^=]*\)=\([^/]*\)/\1=\"\2\"; /g')"
    printf '\n%s\n' "___ Subject ___"
    printf 'Country: %s\n' "$C"
    printf 'Location: %s\n' "$L"
    printf 'State: %s\n' "$ST"
    printf 'Organization: %s\n' "$O"
    printf 'Organizational Unit: %s\n' "$OU"
    printf 'Common Name: %s\n' "${BOLDFACE}${MAGENTA}$CN${ENDFMT}"
}
print_start() {
    CERT=${1}
    sslStartDate="$(openssl x509 -noout -startdate -in "${CERT}" | sed -e 's/\(.*\)=\(.*\)/\2/')"
    if (check_start ${CERT} 0)
    then 
        printf "Ready Since: %s\n" "${GREEN}$sslStartDate${ENDFMT}"
    elif (check_start ${CERT} 7)
    then
        printf "Ready Soon: %s\n" "${YELLOW}$sslStartDate${ENDFMT}"
    else
        printf "NOT READY: %s\n" "${BOLDFACE}${RED}$sslStartDate${ENDFMT}"
    fi
}
print_general() {
    CERT=${1}
    printf "\n${BOLDFACE}${GREEN}___ CORE INFO ON ${CYAN}${FQDN}${GREEN} ___${ENDFMT}\n"
    openssl x509 -noout -subject -issuer -dates -in "${CERT}" | sed -e "s/\(.*\)=\(.*\)/\1=${BOLDFACE}${YELLOW}\2${ENDFMT}/"
}

## Main!
main() {

    echo "$1"
    echo "$2"
    if [ -z "${1}" ]; then printf '%s%s' "$DESCRIPTION" "$USAGE"; exit 0; fi

    ## Accept an alternative CA file
    if [ -n "${2}" ] && [ -f "${2}" ] && (grep -q "BEGIN CERTIFICATE" "${2}")
    then
        CA_ROOTS="${2}" ; export CA_ROOTS
    fi

    if [ -f "${1}" ] && (grep -q "BEGIN CERTIFICATE" "$1")

    ## First Option: Check by File
    then
        CERT_CHAIN="${1}" ; shift
        printf "${GREEN}EXTRACTING CN FROM ${CYAN}${CERT_CHAIN}${GREEN} ...${ENDFMT} "
        eval "$(openssl x509 -noout -subject -in "${CERT_CHAIN}" | sed -e 's/.*CN *=\([^/]*\)/CN="\1"; /g')"
        FQDN="$CN"
        FQDN_IP="$(getip ${FQDN})"
        if [ $? -gt 0 ]
        then
            printf '%s\n' "${RED}NO IP FOR CN \"${CYAN}${BOLDFACE}${FQDN}${ENDFMT}\"" 
        else
            printf '%s\n' "\"${CYAN}${BOLDFACE}${FQDN}${ENDFMT}\" ${GREEN}LIVES AT ${CYAN}${FQDN_IP}${ENDFMT}" 
        fi

    ## Second Option: Check by FQDN
    else
        FQDN="${1}"; shift
        FQDN_IP="$(getip "${FQDN}")"
        if [ -z "$FQDN_IP" ]
        then
            error 1 "Found no IP for \"$FQDN\""
        fi
        while
            CERT_CHAIN=/tmp/${FQDN}_sslchain-$(getsuf).txt
            [ -f "$CERT_CHAIN" ]
        do continue ; done
        touch $CERT_CHAIN

        printf '%s\n' "${GREEN}CONNECTING TO ${CYAN}${FQDN_IP}${GREEN} TO RETRIEVE CERT FOR \"${BOLDFACE}${CYAN}${FQDN}${GREEN}\"...${ENDFMT}"
        printf '%s\n' "" | openssl s_client -showcerts -servername "$FQDN" -connect $FQDN_IP:443 2>/dev/null > $CERT_CHAIN
    fi

    printf '%s\n' "${GREEN}VERIFYING ${BOLDFACE}${CYAN}${FQDN}${ENDFMT} ${GREEN}AGAINST ${CA_ROOTS}"
    verify_out="$(openssl verify -verbose -CAfile "${CA_ROOTS}" -untrusted "${CERT_CHAIN}" "${CERT_CHAIN}")"
    if [ $? -gt 0 ]
    then
        printf '%s\n' "${RED}$verify_out${ENDFMT}"
    else
        printf '%s\n' "${BOLDFACE}${GREEN}$verify_out${ENDFMT}"
    fi

    print_general ${CERT_CHAIN}
    print_subject ${CERT_CHAIN}
    print_altnames ${CERT_CHAIN}
    print_start ${CERT_CHAIN}
    print_expiry ${CERT_CHAIN}

    exit 0
}

main "${@}"
