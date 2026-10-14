#!/usr/bin/env bash -x

codeblock='```'
foo() {
    cat <<EOF

This is PWD now: ${PWD}

This is a code block:
$codeblock
This is PWD now: ${PWD}
$codeblock

EOF
}

foo "${@}"
