#!/usr/local/bin/bash

phrase='the quick brown fox jumps over the lazy dog'
for ((i=0;i<8;i++))
do
    printf 'AF%s: ' "$i"
    tput AF $i
    printf '%s\n' "$phrase"
    tput me
    printf 'Bold: '
    tput md
    tput AF $i
    printf '%s\n' "$phrase"
    tput me
done


## Pretty Colors! For easy sourcing in other scripts.
red='[31m'; export red
green='[32m'; export green
yellow='[33m'; export yellow
blue='[34m'; export blue
magenta='[35m'; export magenta
cyan='[36m'; export cyan

b='[1m'; export b
u='[4m'; export u

# NOTE: 'endfmt' def purposefully left at end here for when $(cat) used on
#       terminal to prevent mangling.
endfmt='[0m'; export endfmt

# See full color list and 5; settings vs 2; or nil:
# https://gist.github.com/blueyed/c8470c2aad3381c33ea3

for ((i=0;i<256;i++))
do
    printf '^[[38;5;%03dm: ' "$i" 
    printf '[38;5;%03dm%s%s\n' "$i" "$phrase" "$endfmt"
done

