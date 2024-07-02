#!/usr/bin/env bash

setvars() {
    printf 'Inherited...\n'
    printf '  * not_exported: "%s"\n' "$not_exported"
    printf '  * exported: "%s"\n' "$exported"

    not_exported="${1:-bar}"
    exported="${1:-bar}"
    printf 'Locally set to "bar"...\n'
    printf '  * not_exported: "%s"\n' "$not_exported"
    printf '  * exported: "%s"\n' "$exported"

    locally_defined="${2:-cud}"
    locally_exported="${2:-cud}"; export locally_exported

    for name in not_exported exported locally_defined locally_exported
    do
        echo "${!name}"
        if [[ -z "$loop_defined" ]]
        then
            local loop_defined="${3:-dit}"
            printf '... set loop_defined to "%s"\n' "$loop_defined"
        fi
        if [[ -z "$loop_exported" ]]
        then
            loop_exported="${3:-dit}"; export loop_exported
        fi
    done

    printf 'Locally set in setvars()...\n'
    printf '  * locally_defined: "%s"\n' "$locally_defined"
    printf '  * locally_exported: "%s"\n' "$locally_exported"
    printf '  * loop_defined: "%s"\n' "$loop_defined"
    printf '  * loop_exported: "%s"\n' "$loop_exported"
}

printvars() {
    printf 'Now in second function scope...\n'
    printf '  * not_exported: "%s"\n' "$not_exported"
    printf '  * exported: "%s"\n' "$exported"
    printf '  * locally_defined: "%s"\n' "$locally_defined"
    printf '  * locally_exported: "%s"\n' "$locally_exported"
    printf '  * loop_defined: "%s"\n' "$loop_defined"
    printf '  * loop_exported: "%s"\n' "$loop_exported"
}

not_exported=foo
exported=foo; export exported

printf 'In the global scope...\n'
printf '  * not_exported: "%s"\n' "$not_exported"
printf '  * exported: "%s"\n' "$exported"
printf '  * locally_defined: "%s"\n' "$locally_defined"
printf '  * locally_exported: "%s"\n' "$locally_exported"

setvars "${@}"

printf 'Back in the global scope...\n'
printf '  * not_exported: "%s"\n' "$not_exported"
printf '  * exported: "%s"\n' "$exported"
printf '  * locally_defined: "%s"\n' "$locally_defined"
printf '  * locally_exported: "%s"\n' "$locally_exported"

printvars

