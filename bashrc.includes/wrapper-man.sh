#!/usr/bin/env bash

# Set colors for man pages. Also, tries to look up a help page with awscli and
# display if no manpages available.
man() {
    PAGER='less -c'
    if (/usr/bin/man -w $@ 1>/dev/null 2>&1)
    then
        env \
        LESS_TERMCAP_mb=$'\E[01;31m' \
        LESS_TERMCAP_md=$'\E[01;38;5;74m' \
        LESS_TERMCAP_me=$'\E[0m' \
        LESS_TERMCAP_se=$'\E[0m' \
        LESS_TERMCAP_so=$'\E[38;5;246m' \
        LESS_TERMCAP_ue=$'\E[0m' \
        LESS_TERMCAP_us=$'\E[04;38;5;146m' \
        man $@
    else
        # Throw out accidental inclusions
        if [ "$1" = "aws" ]; then shift; fi
        if (aws $@ help &>/dev/null)
        then
            aws $@ help | less -rc
        else
            echo "No manual or aws-help entry for $@" 1>&2
        fi
    fi
}
