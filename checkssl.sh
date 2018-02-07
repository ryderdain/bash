#!/bin/sh


## Pretty Colors!
#   NOTE: 'E' def left at end for when `cat` used on terminal
R='[31m'; G='[32m'; Y='[33m'; B='[34m'; M='[35m'; C='[36m';
Bold='[1m';
Underline='[4m';
E='[0m';


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
if [ "`uname`" = "FreeBSD" ]
then
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -jf "
elif [ "`uname`" = "Darwin" ]
then
    ## WARNING: older Bourne Shell is nonexistent on Darwin
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -jf "
elif [ "`uname`" = "Linux" ]
then
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -d "
fi


## Utilities
getip() {
    host -t A -4 "${1}" | grep -m1 -oE '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
    return $?
} 
getsuf() {
    MD5=`which md5sum || which md5`
    head /dev/random | $MD5 | cut -c1-8
}
error() {
    ret_code=${1}; shift
    printf "%s [error]: %s" "`date`" "${@}"
    printf "%s" "$USAGE"
    exit ${ret_code}
}

## Checks
check_expiry() {
    sslEndDate="`openssl x509 -noout -enddate -in ${1}`"
    sslEnd=`$STR2DATE 'notAfter=%b %d %H:%M:%S %Y %Z' "$sslEndDate" +%s`
    [ $sslEnd -gt `date -v +${2:-0}d +%s` ]; return $?
}
check_start() {
    sslStartDate="`openssl x509 -noout -startdate -in ${1}`"
    sslStart=`$STR2DATE 'notBefore=%b %d %H:%M:%S %Y %Z' "$sslStartDate" +%s`
    [ $sslStart -lt `date -v +${2:-0}d +%s` ]; return $?
}

## Printers
print_expiry() {
    CERT=${1}
    sslEndDate="`openssl x509 -noout -enddate -in "${CERT}" | sed -e 's/\(.*\)=\(.*\)/\2/'`"
    if ! (check_expiry ${CERT} 0)
    then 
        printf "EXPIRED: ${Bold}${R}$sslEndDate${E}\n"
    elif ! (check_expiry ${CERT} 30)
    then
        printf "Expires Soon: ${Bold}${Y}$sslEndDate${E}\n"
    else
        printf "Expires: ${G}$sslEndDate${E}\n"
    fi
}
print_altnames() {
    ALTNAMES="`openssl x509 -noout -text -in \"${1}\" | grep -oE 'DNS:.*[^,$ ]' | sed -e 's/,//g;s/DNS:\([^ $]*\)/\1 /g'`"
    count=0
    printf "\n___ Subject Alternative Names ___\n"
    for an in $ALTNAMES
    do
        printf "%02d: %s\n" $count $an
        count=$((count+1))
    done
}
print_subject() {
    cyan="$C"
    eval "`openssl x509 -noout -subject -in \"${1}\" | sed -e 's/[^/]*\/\([^=]*\)=\([^/]*\)/\1=\"\2\"; /g'`"
    printf "\n___ Subject ___
Country: $C
Location: $L
State: $ST
Organization: $O
Organizational Unit: $OU
Common Name: ${Bold}${M}$CN${E}
"
    C="$cyan"
}
print_start() {
    CERT=${1}
    sslStartDate="`openssl x509 -noout -startdate -in "${CERT}" | sed -e 's/\(.*\)=\(.*\)/\2/'`"
    if (check_start ${CERT} 0)
    then 
        printf "Ready Since: ${G}$sslStartDate${E}\n"
    elif (check_start ${CERT} 7)
    then
        printf "Ready Soon: ${Y}$sslStartDate${E}\n"
    else
        printf "NOT READY: ${Bold}${R}$sslStartDate${E}\n"
    fi
}
print_general() {
    CERT=${1}
    printf "\n${Bold}${G}___ CORE INFO ON ${C}${FQDN}${G} ___${E}\n"
    openssl x509 -noout -subject -issuer -dates -in "${CERT}" | sed -e "s/\(.*\)=\(.*\)/\1=${Bold}${Y}\2${E}/"
}

## Main!
main() {
    if [ -z "${1}" ]; then printf "%s%s" "$DESCRIPTION" "$USAGE"; exit 0; fi

    ## Accept an alternative CA file
    if [ -n "${2}" ] && [ -f "${2}" ] && (grep -q "BEGIN CERTIFICATE" "$2")
    then
        CA_ROOTS="${2}" ; export CA_ROOTS
    fi

    if [ -f "${1}" ] && (grep -q "BEGIN CERTIFICATE" "$1")

    ## First Option: Check by File
    then
        CERT_CHAIN="${1}" ; shift
        printf "${G}EXTRACTING CN FROM ${C}${CERT_CHAIN}${G} ...${E} "
        eval "`openssl x509 -noout -subject -in \"${CERT_CHAIN}\" | sed -e 's/.*CN *=\([^/]*\)/CN="\1"; /g'`"
        FQDN="$CN"
        FQDN_IP=`getip ${FQDN}`
        if [ $? -gt 0 ]
        then
            printf "${R}NO IP FOR CN \"${C}${Bold}${FQDN}${E}\"\n" 
        else
            printf "\"${C}${Bold}${FQDN}${E}\" ${G}LIVES AT ${C}${FQDN_IP}${E}\n" 
        fi

    ## Second Option: Check by FQDN
    else
        FQDN="${1}"; shift
        FQDN_IP=`getip ${FQDN}`
        if [ -z "$FQDN_IP" ]
        then
            error 1 "Found no IP for \"$FQDN\""
        fi
        while
            CERT_CHAIN=/tmp/${FQDN}_sslchain-`getsuf`.txt
            [ -f "$CERT_CHAIN" ]
        do continue ; done
        touch $CERT_CHAIN

        printf "${G}CONNECTING TO ${C}${FQDN_IP}${G} TO RETRIEVE CERT FOR \"${Bold}${C}${FQDN}${G}\"...${E}\n"
        printf "\n" | openssl s_client -showcerts -servername "$FQDN" -connect $FQDN_IP:443 2>/dev/null > $CERT_CHAIN
    fi

    printf "${G}VERIFYING ${Bold}${C}${FQDN}${E} ${G}AGAINST $CA_ROOTS\n"
    verify_out="`openssl verify -verbose -CAfile $CA_ROOTS -untrusted $CERT_CHAIN $CERT_CHAIN`"
    if [ $? -gt 0 ]
    then
        printf "${R}$verify_out${E}\n"
    else
        printf "${Bold}${G}$verify_out${E}\n"
    fi

    print_general ${CERT_CHAIN}
    print_subject ${CERT_CHAIN}
    print_altnames ${CERT_CHAIN}
    print_start ${CERT_CHAIN}
    print_expiry ${CERT_CHAIN}

    exit 0
}

main ${@}
