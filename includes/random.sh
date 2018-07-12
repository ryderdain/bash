#!/bin/sh

random() {
    limit=${1:-1}
    modus=
    x=0; while [ $x -lt $limit ]
    do
        modus="9$modus"
        x=$((x+1))
    done
    randbytes="0x$(dd if=/dev/urandom bs=7 count=1 2>/dev/null | xxd -ps)"
    decimal="$(($(printf "%#d" "$randbytes") % $modus))" # reduce 9's for a
                                                         # shorter decimal.
    printf "%d" "$decimal"
    return "$decimal"
}

# Check if sourced or main
$(return >/dev/null 2>&1)
if [ "$?" -ne "0" ]
then
    retval="$(random ${@})"
    printf "%d\n" "$retval"
fi
