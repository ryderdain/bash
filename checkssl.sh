#!/bin/sh


## Pretty Colors!
R='[31m'; G='[32m'; Y='[33m'; B='[34m'; M='[35m'; C='[36m';
Bold='[1m';
Underline='[4m';
E='[0m';

## Compatibility
if [ "`uname -o`" = "FreeBSD" ]
then
    CA_ROOTS=/etc/ssl/cert.pem
    STR2DATE="date -jf "
elif [ "`uname -o`" = "Linux" ]
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
    echo "`date` [error]: ${@}"
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
        echo "EXPIRED: ${Bold}${R}$sslEndDate${E}"
    elif ! (check_expiry ${CERT} 30)
    then
        echo "Expires Soon: ${Bold}${Y}$sslEndDate${E}"
    else
        echo "Expires: ${G}$sslEndDate${E}"
    fi
}
print_altnames() {
    ALTNAMES="`openssl x509 -noout -text -in \"${1}\" | grep -oE 'DNS:.*[^,$ ]' | sed -e 's/,//g;s/DNS:\([^ $]*\)/\1 /g'`"
    count=0
    echo "___ Subject Alternative Names ___"
    for an in $ALTNAMES
    do
        printf "%02d: %s\n" $count $an
        count=$((count+1))
    done
}
print_subject() {
    cyan="$C"
    eval "`openssl x509 -noout -subject -in \"${1}\" | sed -e 's/[^/]*\/\([^=]*\)=\([^/]*\)/\1=\"\2\"; /g'`"
    echo "
___ Subject ___
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
        echo "Ready Since: ${G}$sslStartDate${E}"
    elif (check_start ${CERT} 7)
    then
        echo "Ready Soon: ${Y}$sslStartDate${E}"
    else
        echo "NOT READY: ${Bold}${R}$sslStartDate${E}"
    fi
}
print_general() {
    CERT=${1}
    echo "${Bold}${G}___ ALL INFO ON ${C}${FQDN}${G} ___${E}"
    openssl x509 -noout -subject -issuer -dates -in "${CERT}" | sed -e "s/\(.*\)=\(.*\)/\1=${Bold}${Y}\2${E}/"
}

## Main!
main() {
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

    echo "${G}CONNECTING TO ${C}${FQDN_IP}${G} TO RETRIEVE CERT FOR \"${Bold}${C}${FQDN}${G}\"...${E}"
    echo "" | openssl s_client -showcerts -servername "$FQDN" -connect $FQDN_IP:443 2>/dev/null > $CERT_CHAIN

    echo -n "${G}VERIFYING ${Bold}${C}${FQDN}${E} ${G}AGAINST $CA_ROOTS via "
    verify_out="`openssl verify -verbose -CAfile $CA_ROOTS -untrusted $CERT_CHAIN $CERT_CHAIN`"
    if [ $? -gt 0 ]
    then
        echo "${R}$verify_out${E}"
    else
        echo "${Bold}${G}$verify_out${E}"
    fi

    print_general ${CERT_CHAIN}
    print_subject ${CERT_CHAIN}
    print_altnames ${CERT_CHAIN}
    print_start ${CERT_CHAIN}
    print_expiry ${CERT_CHAIN}

    rm $CERT_CHAIN
    exit 0
}

main ${@}
