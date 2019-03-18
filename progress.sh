#!/usr/bin/env bash

usage() {
    let return_code=${1}
    echo "
Usage: $0 <procfile> <logfile>
    
    Takes two files as input, and reports progress based on the
    how the logfile's length compares to the file being procesed. 
"
    if [ -n $return_code ]; then
        exit $return_code
    else
        exit 1
    fi
}

len() {
    echo `wc -l ${1} | awk '{ print $1; }'`
}

# Get column, row lengths of tty for FreeBSD via tput
setrow() {
    row=$(tput lines)
    echo $row
}
row=`setrow`
setcol() {
    col=$(tput columns)
    echo $col
}
col=`setcol`

trap "col=`setcol`" 28
declare -a bar
let winlen=$(( $col )) ## Adjust gap based on printf line below
let c=0
run_len=$(len ${1})
log_len=$(len ${2})

while [[ $c -lt $winlen ]]
do
    progress=$(printf "%.0f" `echo "scale=10 ; ($log_len/$run_len) * 100" | bc`)
    comp=$(printf "%.0f" `echo "scale=10 ; ($c/$winlen) * 100" | bc`)

    pct=$(printf "%.4f" `echo "scale=10 ; ($log_len/$run_len) * 100" | bc`)

    if [[ $progress -ge $comp ]]
    then
        c=$((c+1))
        bar[$c]='#'
    fi
    header="($log_len/$run_len):"
    winlen=$(( $col - ${#header} - ${#pct} - 5 ))
    printf "\e[K${header} %-${winlen}s (%.4f%%)\r" $(sed 's/ //g' <<<${bar[*]}) $pct
    sleep 1
    log_len=$(len ${2})
done

