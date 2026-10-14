#!/usr/bin/env bash

printf '## ===== TEST ONE: Simple Mid-Process Loop =====\n\n'

set -x

zeta=1

for number in $(echo {1..3})
do
    let zeta="$number"
    if [ $zeta = 3 ]; then break ; fi
done

set +x

printf '## +++++ TEST ONE RESULT: zeta = %s +++++\n\n' "$zeta"


printf '## ===== TEST TWO: Looping Over Piped-in Input =====\n\n'


set -x

zeta=1

echo {1..3} | for number in $(</dev/stdin)
do
    let zeta="$number"
    if [ $zeta = 3 ]; then break ; fi
done

set +x


printf '\n## +++++ TEST ONE RESULT: zeta = %s +++++\n\n' "$zeta"

printf '## ===== TEST THREE: Reading from a Named Pipe =====\n\n'

set -x

zeta=1

pipe="$(mktemp -u)"
mkfifo "$pipe"

echo {1..3} > "$pipe" & 

for number in $(cat $pipe)
do
    let zeta="$number"
    if [ $zeta = 3 ]; then break ; fi
done

set +x
rm -v "$pipe"



printf '\n## +++++ TEST THREE RESULT: zeta = %s +++++\n' "$zeta"
