#!/usr/bin/env bash

tests=(foo bar chu dit)

for arg in "${@}"
do
    case $arg in 
    "$(echo ${tests[@]}|sed 's/ /|/g')")
        echo found $arg;;
    ${tests[@]})
        echo found in arr $arg;;
    foo|bar|chu|dit)
        echo found in arr $arg;;
    *)
        echo catchall $arg;;
    esac
done

