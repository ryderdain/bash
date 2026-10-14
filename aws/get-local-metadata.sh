#!/usr/bin/env bash

# If all you have is a bash shell on an ec2 host, this can get some information for you.

get_page() {

    # Wrap output to guarantee an end line

    exec 3<>/dev/tcp/169.254.169.254/80
    printf "GET %s HTTP/1.1\r\nHost: 169.254.169.254\r\nConnection: close\r\n\r\n" "${1:-/}" >&3
    ok_re='HTTP/[0-9.]+ 200 OK'
    read -r response <&3
    if [[ "$response" =~ $ok_re ]]
    then
        cat <&3
        printf '\n'
        exec 3<>-
        return 0
    else
        exec 3<>-
        return 1
    fi
}

request() {
    
    # Return results, not headers.

    headers_re='(HTTP|Content-Type|Accept-Ranges|Last-Modified|Content-Length|Date|Server|Connection)'
    get_page "$1" | while read -r line
    do
        if [[ "$line" =~ $headers_re ]]
        then
            continue
        else
            printf '%s\n' "$(echo "$line"|sed 's/\r$//')"
        fi
    done 
}

get_all() {

    # Recurse through paths and print results

    local path="${1:-/latest/meta-data/}"
    mapfile -t categories < <(request ${path})
    for category in ${categories[@]}
    do
        if [[ "${category: -1}" = '/' ]]
        then 
            get_all "${path}${category}"
        else
            values=( $(request ${path}/$category) )
            if [[ ${#values[@]} -gt 0 ]]
            then
                printf '%s:\n' "${path}${category}"
                json_re='(\[|\{|<)'
                xml_re='<\?[xX][mM][lL]'
                if [[ "${values[0]:0:1}" =~ $json_re ]]
                then
                    printf '\t%s\n' "${values[*]}"
                elif [[ "${values[0]:0:5}" =~ $xml_re ]]
                then
                    printf '\t%s\n' "${values[*]}"
                else
                    for v in ${values[@]}
                    do
                       printf '\t%s\n' "$v"
                    done
                fi
            else
                printf '%s: none' "${path}"
            fi
            #echo ${values[@]}
            printf '\n'
        fi
    done
}

if [[ $# -gt 0 ]]
then 
    request ${@}
else
    get_all /latest/meta-data/
    get_all /latest/dynamic/
    get_all /latest/user-data/
fi
