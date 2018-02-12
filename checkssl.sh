#!/bin/sh


## Pretty Colors!
#   NOTE: 'E' def left at end for when $(cat) used on terminal
red='[31m';
green='[32m';
yellow='[33m';
#blue='[34m';
magenta='[35m';
cyan='[36m';
bold='[1m';
#underline='[4m';
endfmt='[0m';


## Usage
description="
Pretty-prints useful info about the SSL certificate. Can fetch via DNS
entry or checks a file. Can pass a CA root file as a second argument.
"
usage="
Usage:
    $0 <fqdn|file> [ <cafile> ]

"

## Compatibility
system="$(uname)"
case "$system" in
FreeBSD|Darwin)
    ca_roots=/etc/ssl/cert.pem
    md5_cmd='/sbin/md5 '
    sed_cmd='sed -E -e'
    ssl_str2date() { target="$(printf '%s\n' "${1}" | cut -d'=' -f2)"; date -jf "%b %d %H:%M:%S %Y %Z" "$target" '+%Y%m%d'; }
    reldate() { n="${1:-0}" ; [ "$n" -ge 0 ] && n="+$1" ; date -v "${n}d" "+%Y%m%d"; }
    ;;
Linux|*)
    ca_roots=/etc/ssl/certs/certSIGN_ROOT_CA.pem
    md5_cmd='/usr/bin/md5sum -b '
    sed_cmd='sed -r -e'
    ssl_str2date() { target="$(printf '%s\n' "${1}" | cut -d'=' -f2)"; date --date="$target" '+%Y%m%d'; }
    reldate() { n="${1:-0}" ; [ "$n" -ge 0 ] && n="+$1" ; date --date="${n} days" '+%Y%m%d'; }
    ;;
esac


## Utilities
error() {
    ret_code=${1}; shift
    printf '%s [error]: %s' "$(date)" "${@}"
    printf '%s' "$usage"
    exit "${ret_code}"
}
getip() {
    host -t A -4 "${1}" | grep -m1 -oE '([0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})'
    return $?
} 
getsuf() {
    dd if=/dev/random bs=128 count=1 2>/dev/null | $md5_cmd | cut -c1-8
}
list_elements() {
    count=0
    printf '%s\n' "${@}" | tr -s '\008\010\011\012\013\014\015\040' '\012' | while read -r element
    do
        printf '%02d: %s\n' "$count" "$element"
        count="$((count+1))"
    done
}

## Checks
check_expiry() {
    sslEndDate="$(openssl x509 -noout -enddate -in "${1}")"
    sslEnd="$(ssl_str2date "${sslEndDate}")"
    [ "$sslEnd" -gt "$(reldate "${2:-0}")" ]; return "$?"
}
check_start() {
    sslStartDate="$(openssl x509 -noout -startdate -in "${1}")"
    sslStart="$(ssl_str2date "${sslStartDate}")"
    [ "$sslStart" -lt "$(reldate "${2:-0}")" ]; return "$?"
}
pluck() {
    delimiter="${1}"; shift
    subject_header="${1}"; shift
    subject_line="$(printf '%s' "$1" | $sed_cmd 's/^subject= *//')"; shift
    printf '%s\n' "$(printf '%s\n' "${subject_line}" |\
         grep -oE "(${delimiter}|^)${subject_header} *= *([^${delimiter}]+)" |\
         cut -d'=' -f2)"
}

## Printers
print_expiry() {
    cert_chain=${1}
    sslEndDate="$(openssl x509 -noout -enddate -in "${cert_chain}" | awk '{ split($0,a,"="); print a[2];}')"
    if ! (check_expiry "${cert_chain}" 0)
    then 
        printf 'EXPIRED: %s\n' "${bold}${red}$sslEndDate${endfmt}"
    elif ! (check_expiry "${cert_chain}" 30)
    then
        printf 'Expires Soon: %s\n' "${bold}${yellow}$sslEndDate${endfmt}"
    else
        printf 'Expires: %s\n' "${green}$sslEndDate${endfmt}"
    fi
}
print_altnames() {
    printf '\n%s\n' "___ Subject Alternative Names ___"
    altnames="$(openssl x509 -noout -text -in "${1}" | grep -oE 'DNS:([^, $]+)')"
    common_name_list="$(printf '%s' "$altnames" | $sed_cmd 's/DNS:([^, $]+)/\1/g')"
    list_elements "$common_name_list"
}
print_subject() {
    # Parse the subject in RFC's comma-separated format 'CN=example.com,OU=...'
    # see RFC2253 for more info on string returned
    subject_line="$(openssl x509 -noout -nameopt RFC2253 -subject -in "${1}" | cut -d' ' -f2-)"
    printf '\n%s\n' "___ Subject ___"
    printf 'Country: %s\n' "$(pluck , C "$subject_line")"
    printf 'Location: %s\n' "$(pluck , L "$subject_line")"
    printf 'State: %s\n' "$(pluck , ST "$subject_line")"
    printf 'Organization: %s\n' "$(pluck , O "$subject_line")"
    printf 'Organizational Unit: %s\n' "$(pluck , OU "$subject_line")"
    printf 'Common Name: %s\n' "${bold}${magenta}$(pluck , CN "$subject_line")${endfmt}"
}
print_start() {
    cert_chain=${1}
    sslStartDate="$(openssl x509 -noout -startdate -in "${cert_chain}" | awk '{ split($0,a,"="); print a[2];}')"
    if (check_start "${cert_chain}" 0)
    then 
        printf 'Ready Since: %s\n' "${green}$sslStartDate${endfmt}"
    elif (check_start "${cert_chain}" 7)
    then
        printf 'Ready Soon: %s\n' "${yellow}$sslStartDate${endfmt}"
    else
        printf 'NOT READY: %s\n' "${bold}${red}$sslStartDate${endfmt}"
    fi
}
print_general() {
    cert_chain=${1}
    printf '\n%s\n' "${bold}${green}___ CORE INFO ON ${cyan}${fqdn}${green} ___${endfmt}"
    gen_info="$(openssl x509 -noout -subject -issuer -dates -in "${cert_chain}" | $sed_cmd 's/(.*)=(.*)/\1=\2/')"
    printf '%s\n' "$gen_info"
}

## Main!
main() {
    if [ -z "${1}" ]; then printf '%s%s' "$description" "$usage"; exit 0; fi

    ## Accept an alternative CA file
    if [ -n "${2}" ] && [ -f "${2}" ] && (grep -q "BEGIN CERTIFICATE" "${2}")
    then
        ca_roots="${2}" ; export ca_roots
    fi

    if [ -f "${1}" ] && (grep -q "BEGIN CERTIFICATE" "$1")

    ## First Option: Check by File
    then
        cert_chain="${1}" ; shift
        printf '%s' "${green}EXTRACTING CN FROM ${cyan}${cert_chain}${green} ...${endfmt} "
        subject_line="$(openssl x509 -noout -nameopt RFC2253 -subject -in "${cert_chain}")"
        common_name="$(pluck , CN "$subject_line")"
        fqdn="$common_name"
        if fqdn_ip="$(getip "${fqdn}")"
        then
            printf '%s\n' "\"${cyan}${bold}${fqdn}${endfmt}\" ${green}LIVES AT ${cyan}${fqdn_ip}${endfmt}" 
        else
            printf '%s\n' "${red}NO IP FOR CN \"${cyan}${bold}${fqdn}${endfmt}\"" 
        fi

    ## Second Option: Check by fqdn
    else
        fqdn="${1}"; shift
        fqdn_ip="$(getip "${fqdn}")"
        if [ -z "$fqdn_ip" ]
        then
            error 1 "Found no IP for \"$fqdn\""
        fi
        while
            cert_chain=/tmp/${fqdn}_sslchain-$(getsuf).txt
            [ -f "$cert_chain" ]
        do continue ; done
        touch "$cert_chain"

        printf '%s\n' "${green}CONNECTING TO ${cyan}${fqdn_ip}${green} TO RETRIEVE CERTIFICATE FOR \"${bold}${cyan}${fqdn}${green}\"...${endfmt}"
        printf '%s\n' "" | openssl s_client -showcerts -servername "$fqdn" -connect "$fqdn_ip":443 2>/dev/null > "$cert_chain"
    fi

    printf '%s\n' "${green}VERIFYING ${bold}${cyan}${fqdn}${endfmt} ${green}AGAINST ${ca_roots}"
    if verify_out="$(openssl verify -verbose -CAfile "${ca_roots}" -untrusted "${cert_chain}" "${cert_chain}")"
    then
        printf '%s\n' "${bold}${green}$verify_out${endfmt}"
    else
        printf '%s\n' "${red}$verify_out${endfmt}"
    fi

    print_general "${cert_chain}"
    print_subject "${cert_chain}"
    print_altnames "${cert_chain}"
    print_start "${cert_chain}"
    print_expiry "${cert_chain}"

    exit 0
}

main "${@}"
