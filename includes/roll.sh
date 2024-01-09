#!/usr/bin/env bash

roll() { 
    # Roll a number between 1 and the limit, defaults to six.
    printf "%${ROLL_FMT:-d}\n" "$(( ($RANDOM % ${1:-6}) + 1))"
}
