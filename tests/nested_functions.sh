#!/usr/bin/env bash 


level2() {
    echo "$0 in ${FUNCNAME[0]}"
    echo "Full tree: ${FUNCNAME[@]@A}"
    level1
}

level1() {
    [[ ${#FUNCNAME[@]} -lt 12 ]] || return 0
    echo "$0 in ${FUNCNAME[0]}"
    echo "Called by ${FUNCNAME[1]}"
    echo "Full tree: ${FUNCNAME[@]@A}"
    level2
}

level0() {
    echo "$0 in ${FUNCNAME[0]}"
    echo "Full tree: ${FUNCNAME[@]@A}"
    level1
}

echo "Run $0..."
level0
