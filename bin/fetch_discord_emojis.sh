#!/usr/bin/env bash

# For parsing pasted lines of emojis/reactions as "copy text" from mobile app (browser/OS app only copies emoji "name")
fetch_discord_emojis() { 
    for arg in "${@}"
    do
        if [[ -r "$arg" ]]
        then
            read -ra emojis < "$arg"
        else
            read -ra emojis <<<"${arg}"
        fi
        for x in "${emojis[@]}" ; do
            IFS=: read -ra arr <<<"${x}:"
            case "${arr[0]}" in
                '<') suffix=".png" ;;
                '<a') suffix=".gif" ;;
                '*') continue ;; 
            esac
            src="https://cdn.discordapp.com/emojis/${arr[2]/>/$suffix}"
            out="$emojis_dir/${arr[1]}$suffix"
            curl -s -o "$out" "$src"
        done
    done
}

# Version two
fetch_discord_emojis_rx() { 
    for arg in "${@}"
    do 
        if [[ -r "$arg" ]]
        then
            read -ra emojis < "$arg"
        else
            emojis=()
            while [[ $arg ]]
            do
                [[ $arg =~ ^([^ ]*)( |$) ]]
                emojis+=("${BASH_REMATCH[1]}")
                arg="${arg#"$BASH_REMATCH"}"
            done
        fi
        for emoji in "${emojis[@]}"
        do
            arr=()
            while [[ $emoji ]]
            do
                [[ $emoji =~ ^([^:]*)(:|$) ]]
                arr+=("${BASH_REMATCH[1]}")
                emoji="${emoji#"$BASH_REMATCH"}"
            done
            case "${arr[0]}" in
                '<') suffix=".png" ;;
                '<a') suffix=".gif" ;;
                '*') continue ;; 
            esac
            src="https://cdn.discordapp.com/emojis/${arr[2]/>/$suffix}"
            out="$emojis_dir/${arr[1]}$suffix"
            curl -s -o "$out" "$src"
        done
    done
}

# version three
get_new_filename() {
    local file="$1";
    local base ext newfile n;
    ext=""
    [[ "$file" == *.* ]] && { ext=".${file##*.}";
    base="${file%.*}"; } || { base="$file"; };
    newfile="$file";
    n=1; 
    while [[ -e "$newfile" ]];
    do
        newfile="${base}_$n$ext";
        ((n++));
    done; 
    echo "$newfile";
}

while read -r emt
do
    x=($(tr '>:<' ' ' <<<"$emt"))
    if [[ ${#x[@]} -gt 2 ]]
    then
        ext="gif" id="${x[2]}"
        fn="$(get_new_filename "${x[1]}.${ext}")"
    else
        ext="png" id="${x[1]}"
        fn="$(get_new_filename "${x[0]}.${ext}")"
    fi
    curl -s -o "${fn}.${ext}" "https://cdn.discordapp.com/emojis/${id}.${ext}"
done

# test to compare
func_test() {
    tempfd_emojis_dir="$(mktemp -d "/tmp/emojis.XXXX")"
    regex_emojis_dir="$(mktemp -d "/tmp/emojis.XXXX")"

    printf '\nRun tempfd version test...'
    time emojis_dir="$tempfd_emojis_dir" fetch_discord_emojis "$@"

    printf '\nRun regex version test...'
    time emojis_dir="$regex_emojis_dir" fetch_discord_emojis_rx "$@"
    
    printf '\ncleaning up...\n'
    rm -rv "$tempfd_emojis_dir" "$regex_emojis_dir"
}

emojis_dir="$(mktemp -d "/tmp/emojis.XXXX")" fetch_discord_emojis_rx "$@"
