#!/usr/bin/env bash

. includes/error.sh

hex2string() {
  I=0
  while [[ $I -lt ${#1} ]]
  do
    echo -en "\x"${1:$I:2}
    let "I += 2"
  done
}
split_fqdn() {
    :
}

# Example base case; working qbsd.io query string
#exec {fd}<>/dev/udp/1.1.1.1/53
#query_head='\x5a\xa2\x01\x02\x00\x01\x00\x00\x00\x00\x00\x01'
#query_tail='\x00\x00\x01\x00\x01\x00\x00\x29\x10\x00\x00\x00\x00\x00\x00\x00'
#encoded_fqdnhex='\x04\x71\x62\x73\x64\x02\x69\x6f\x00'
#echo -e "${query_head}${query_tail}
#xxd <&$fd # any encoder will do

# Hexification
txn_id='\xfa\xbe' # can be arbitrary, returned by resolver
query_head='\x01\x02\x00\x01\x00\x00\x00\x00' # standard A IN query
addtl_rr_count='\x00\x01' # one additional record (standard)
query_tail='\x00\x00\x01\x00\x01'
addtl_rr='\x00\x00\x29\x10\x00\x00\x00\x00\x00\x00\x00' # for testing

# Test Case
# TODO: replace with python-like 'split(".")' to take arbitrary domain.
fqdn="${1:-lookatmy.horse}" # default lookup: "lookatmy.horse"
# Arbitrary CLI input (subdomains will require a loop)
fqdn_segments=( ${fqdn/./ } )

if [[ "${fqdn: -1:1}" != '.' ]]
then
    tld="${fqdn##*.}"

    apex="${fqdn%%.*}"
    apex="${apex##*.}"
else
    tld="${fqdn##*.}"
    tld="${tld##*.}"

    apex="${fqdn%%.*}"
    apex="${apex%%.*}"
    apex="${apex##*.}"
fi

# Domain segment encoding 
apex_length="$(printf '\\x%02x' ${#apex})"
tld_length="$(printf '\\x%02x' ${#tld})"

apex_as_hex=$(echo -n "$apex" | xxd -p | sed 's/\(..\)/\\x\1/g')
tld_as_hex=$(echo -n "$tld" | xxd -p | sed 's/\(..\)/\\x\1/g')

#exec {fd}<>/dev/udp/1.1.1.1/53
exec {fd}<>/dev/udp/8.8.8.8/53
echo "OPENED FD $fd"

## WORKING / echo uses '-e', printf implictly applies encoding
#echo -e "${txn_id}${query_head}${apex_length}${apex_as_hex}${tld_length}${tld_as_hex}${query_tail}" >&$fd
printf '%b' "${txn_id}${query_head}${addtl_rr_count}${apex_length}${apex_as_hex}${tld_length}${tld_as_hex}${query_tail}${addtl_rr}" >&$fd
swap_IFS="$IFS"
IFS=""
# read doesn't buffer the udp output. Would mapfile...?
count=0
coproc cat <&$fd 
while read -r -t 1 -d '' -n 1 response_byte
do
    if [[ -z $response_byte  ]]
    then
        printf '%b' '\x00' | xxd
        ((count++))
        if [[ $count -gt 6 ]]
        then
            exec {fd}<&-
            exit 0
        fi
    else
        count=0
    fi
    printf '%b' "$response_byte" | xxd
done <&${COPROC[0]}
IFS="$swap_IFS"

## Below does not execute; read appears to wait for termination of line, which isn't guaranteed.
# echo "ENTERING WHILE LOOP"
# while read -r -N 4 response -u $fd
# do 
#     echo "IN WHILE LOOP"
#     echo "${response}" | xxd
# done
