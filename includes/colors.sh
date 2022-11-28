#!/usr/bin/env bash

## Pretty Colors! For easy sourcing in other scripts. Works anywhere a TTY is emulated.

# These are foreground colors only.
black='\033[30m'; export black
red='\033[31m'; export red
green='\033[32m'; export green
yellow='\033[33m'; export yellow
blue='\033[34m'; export blue
magenta='\033[35m'; export magenta
cyan='\033[36m'; export cyan
white='\033[37m'; export white

bright_black='\033[90m'; export bright_black
bright_red='\033[91m'; export bright_red
bright_green='\033[92m'; export bright_green
bright_yellow='\033[93m'; export bright_yellow
bright_blue='\033[94m'; export bright_blue
bright_magenta='\033[95m'; export bright_magenta
bright_cyan='\033[96m'; export bright_cyan
bright_white='\033[97m'; export bright_white

# Background colors
bg_black='\033[40m'; export bg_black
bg_red='\033[41m'; export bg_red
bg_green='\033[42m'; export bg_green
bg_yellow='\033[43m'; export bg_yellow
bg_blue='\033[44m'; export bg_blue
bg_magenta='\033[45m'; export bg_magenta
bg_cyan='\033[46m'; export bg_cyan
bg_white='\033[47m'; export bg_white

bg_bright_black='\033[100m'; export bg_bright_black
bg_bright_red='\033[101m'; export bg_bright_red
bg_bright_green='\033[102m'; export bg_bright_green
bg_bright_yellow='\033[103m'; export bg_bright_yellow
bg_bright_blue='\033[104m'; export bg_bright_blue
bg_bright_magenta='\033[105m'; export bg_bright_magenta
bg_bright_cyan='\033[106m'; export bg_bright_cyan
bg_bright_white='\033[107m'; export bg_bright_white

bold='\033[1m'; export bold
underline='\033[4m'; export underline

# NOTE: 'endfmt' def purposefully left at end here for when $(cat) used on
#       terminal to prevent mangling.
endfmt='\033[0m'; export endfmt

# See full color list and 5; settings vs 2; or nil:
# https://gist.github.com/blueyed/c8470c2aad3381c33ea3

function print_color_references() {
    # Print out basic color list by name, retain order by index for fg16/bg16

    extended_colors=
    if [[ "$1" =~ ^(-a|--all)$ ]] 
    then
        extended_colors=1
        shift  
    fi

    phrase="${1:-the quick brown fox jumps over the lazy dog}"
    
    esc='\033[' # for printf

    fg16=({30..37}m {90..97}m)
    bg16=({40..47}m {100..107}m)
    colors=(
        black
        red
        green
        yellow
        blue
        magenta
        cyan
        white
        bright_black
        bright_red
        bright_green
        bright_yellow
        bright_blue
        bright_magenta
        bright_cyan
        bright_white
    )
    printf '==== Basic Color Selection ====\n'
    for c in "${!colors[@]}"
    do
        # printf replacements don't preserve char escapes
        # using %03d results in 'invalid octal number'
        printf "code %s: $esc${fg16[$c]}%s$endfmt (%s)\n" "$esc${fg16[$c]}" "$phrase" "${colors[$c]}" 
    done
    printf '\n'

    if [[ "$extended_colors" ]]
    then
        # Extended color selection
        fgcsel='38;5'
        fg256sel='38;2'
        bgcsel='48;5'
        bg256sel='48;2'

        c256=({000..255})

        printf '==== Extended Color Selection ====\n'
        for c in "${c256[@]}"
        do
            printf "code %s%s%s: $esc$fgcsel;%sm%s$endfmt\n" "$esc" "$fgcsel" "$c" "$c" "$phrase"
        done
        printf '\n'
    fi
}

function short_vars_for_colors() {
    # Source a call to this function's output for one-place color vars
    # Skips "block", doesn't use background shorthand

    fg16=({31..37}m {91..97}m)
    colors=(
        red
        green
        yellow
        blue
        magenta
        cyan
        white
        bright_red
        bright_green
        bright_yellow
        bright_blue
        bright_magenta
        bright_cyan
        bright_white
    )
    for c in "${!colors[@]}"
    do
        if [[ "${colors[$c]%_*}" = "bright" ]]
        then
            var="${colors[$((c-7))]^^}"
        else
            var="${colors[$c]}"
        fi
        var=${var:0:1}
        printf '%s=%s\n' "$var" '\\033['"${fg16[$c]}" 
    done
    printf 'Q="$endfmt"\n' # Think 'Quit'
    printf 'U="$underline"\n' 
    printf 'E="$bold"\n' # E for 'Emphasis'
}
